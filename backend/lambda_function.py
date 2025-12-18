import json
import os
import uuid
import io
from datetime import datetime
import boto3
import qrcode
from PIL import Image

def lambda_handler(event, context):
    try:
        # Handle CORS preflight requests
        if event.get('requestContext', {}).get('http', {}).get('method') == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS',
                    'Access-Control-Allow-Headers': 'Content-Type'
                }
            }
        
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event.get('body', {})
        
        text_to_encode = body.get('text_to_encode')
        if not text_to_encode:
            return {
                'statusCode': 400,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({'error': 'text_to_encode is required'})
            }
        
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(text_to_encode)
        qr.make(fit=True)
        
        qr_image = qr.make_image(fill_color="black", back_color="white")
        
        img_buffer = io.BytesIO()
        qr_image.save(img_buffer, format='PNG')
        img_buffer.seek(0)
        
        unique_id = str(uuid.uuid4())
        s3_key = f"qr-codes/{unique_id}.png"
        
        s3_client = boto3.client('s3')
        bucket_name = os.environ['S3_BUCKET_NAME']
        
        s3_client.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=img_buffer.getvalue(),
            ContentType='image/png'
        )
        
        s3_url = f"https://{bucket_name}.s3.amazonaws.com/{s3_key}"
        
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])
        
        table.put_item(
            Item={
                'id': unique_id,
                'text': text_to_encode,
                's3_url': s3_url,
                'created_at': datetime.utcnow().isoformat()
            }
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'id': unique_id,
                's3_url': s3_url,
                'message': 'QR code generated successfully'
            })
        }
    
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'error': str(e)})
        }