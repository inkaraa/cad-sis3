#!/usr/bin/env bash
# Delete everything for one environment:  ./destroy.sh <env>
set -euo pipefail

ENV="${1:?usage: ./destroy.sh <env>}"
export AWS_REGION="${AWS_REGION:-eu-north-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
APP_STACK="sis3-${ENV}-app"
BASE_STACK="sis3-${ENV}-base"

echo "==> Deleting $APP_STACK (ALB, ECS, VPC, queues, Lambda, table, roles, logs)"
aws cloudformation delete-stack --stack-name "$APP_STACK"
aws cloudformation wait stack-delete-complete --stack-name "$APP_STACK"

BUCKET=$(aws cloudformation describe-stacks --stack-name "$BASE_STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='ArtifactsBucketName'].OutputValue" --output text 2>/dev/null || true)
if [ -n "$BUCKET" ] && [ "$BUCKET" != "None" ]; then
  echo "==> Emptying bucket $BUCKET"
  aws s3 rm "s3://$BUCKET" --recursive
fi

echo "==> Deleting $BASE_STACK (ECR repository with images, artifacts bucket)"
aws cloudformation delete-stack --stack-name "$BASE_STACK"
aws cloudformation wait stack-delete-complete --stack-name "$BASE_STACK"
echo "Done: $ENV removed."
