#!/usr/bin/env bash
# One command to deploy the whole system:  ./deploy.sh [env]
# Examples:  ./deploy.sh dev      ./deploy.sh defence
set -euo pipefail

ENV="${1:-dev}"
export AWS_REGION="${AWS_REGION:-eu-north-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
BASE_STACK="sis3-${ENV}-base"
APP_STACK="sis3-${ENV}-app"
cd "$(dirname "$0")"

out() {
  aws cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text
}

if [ -n "$(git status --porcelain -- app consumer)" ]; then
  echo "ERROR: commit your changes in app/ or consumer/ first (the image tag is a git commit)"
  exit 1
fi

echo "==> 1/5 Lint templates"
if command -v cfn-lint >/dev/null 2>&1; then
  cfn-lint -i W3002 -- infra/base.yaml infra/app.yaml
else
  echo "    cfn-lint not installed, skipping"
fi

echo "==> 2/5 Base stack $BASE_STACK (ECR repository + artifacts bucket)"
aws cloudformation deploy --stack-name "$BASE_STACK" --template-file infra/base.yaml \
  --parameter-overrides Env="$ENV" --no-fail-on-empty-changeset
REPO=$(out "$BASE_STACK" RepoUri)
BUCKET=$(out "$BASE_STACK" ArtifactsBucketName)

echo "==> 3/5 Container image (tag = last git commit that changed app/, never latest)"
TAG=$(git log -1 --format=%h -- app)
IMAGE="$REPO:$TAG"
if aws ecr describe-images --repository-name "${REPO#*/}" --image-ids imageTag="$TAG" >/dev/null 2>&1; then
  echo "    $IMAGE already in ECR"
else
  aws ecr get-login-password | docker login --username AWS --password-stdin "${REPO%%/*}"
  docker build --platform linux/arm64 -t "$IMAGE" ./app
  for attempt in 1 2 3 4 5 6 7 8; do
    if docker push "$IMAGE"; then break; fi
    echo "    push failed (attempt $attempt), retrying..."
    sleep 10
  done
  aws ecr describe-images --repository-name "${REPO#*/}" --image-ids imageTag="$TAG" >/dev/null
fi

echo "==> 4/5 Package Lambda code and deploy $APP_STACK"
mkdir -p build
aws cloudformation package --template-file infra/app.yaml --s3-bucket "$BUCKET" \
  --output-template-file "build/app.$ENV.yaml"
aws cloudformation deploy --stack-name "$APP_STACK" --template-file "build/app.$ENV.yaml" \
  --parameter-overrides Env="$ENV" ImageUri="$IMAGE" \
  --capabilities CAPABILITY_IAM --no-fail-on-empty-changeset

echo "==> 5/5 Done"
URL=$(out "$APP_STACK" AlbUrl)
echo "API: $URL"
curl -s --max-time 10 "$URL/health" && echo "  <- /health"
