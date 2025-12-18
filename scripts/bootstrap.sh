#!/bin/bash

# Bootstrap script to create S3 bucket for Terraform state if it doesn't exist

BUCKET_NAME="my-terraform-state-bucket-superman-harry"
AWS_REGION="us-east-1"

echo "Checking if S3 bucket $BUCKET_NAME exists..."

# Check if bucket exists
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "✅ S3 bucket $BUCKET_NAME already exists"
else
    echo "🔄 Creating S3 bucket $BUCKET_NAME..."
    
    # Create the bucket
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION"
    
    # Enable versioning for state file protection
    echo "🔄 Enabling versioning on bucket..."
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Enable server-side encryption
    echo "🔄 Enabling server-side encryption..."
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": true
            }]
        }'
    
    # Block public access
    echo "🔄 Blocking public access..."
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    
    echo "✅ S3 bucket $BUCKET_NAME created and configured successfully"
fi

echo "🚀 Ready for Terraform initialization!"