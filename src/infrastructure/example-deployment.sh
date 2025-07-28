#!/bin/bash

# Example deployment script for Lambda Auto-Repair System
# This script demonstrates how to deploy the system to different environments

set -e

echo "=== Lambda Auto-Repair System - Example Deployment ==="

# Example 1: Deploy to development environment
echo "Example 1: Development Environment Deployment"
echo "./deploy.sh --environment dev --email dev-team@example.com"
echo ""

# Example 2: Deploy to staging with approval workflow
echo "Example 2: Staging Environment with Approval Workflow"
echo "./deploy.sh --environment staging --email staging-team@example.com --enable-approval"
echo ""

# Example 3: Deploy to production with all options
echo "Example 3: Production Environment (Full Configuration)"
echo "./deploy.sh \\"
echo "  --environment prod \\"
echo "  --email ops-team@example.com \\"
echo "  --enable-approval \\"
echo "  --knowledge-base-id kb-1234567890abcdef \\"
echo "  --region us-west-2"
echo ""

# Example 4: Validate deployment
echo "Example 4: Validate Deployment"
echo "./validate-deployment.sh --environment prod --region us-west-2"
echo ""

# Example 5: Dry run validation
echo "Example 5: Dry Run (Template Validation Only)"
echo "./deploy.sh --environment dev --email test@example.com --dry-run"
echo ""

echo "=== Parameter File Usage ==="
echo "You can also customize parameters by editing the files in parameters/ directory:"
echo "- parameters/dev.json     - Development environment settings"
echo "- parameters/staging.json - Staging environment settings"
echo "- parameters/prod.json    - Production environment settings"
echo ""

echo "=== Manual CloudFormation Deployment ==="
echo "If you prefer to use AWS CLI directly:"
echo ""
echo "# Deploy main stack"
echo "aws cloudformation create-stack \\"
echo "  --stack-name lambda-auto-repair-main-dev \\"
echo "  --template-body file://lambda-auto-repair-main.yaml \\"
echo "  --parameters ParameterKey=Environment,ParameterValue=dev \\"
echo "               ParameterKey=NotificationEmail,ParameterValue=admin@example.com \\"
echo "  --capabilities CAPABILITY_NAMED_IAM"
echo ""
echo "# Deploy functions stack"
echo "aws cloudformation create-stack \\"
echo "  --stack-name lambda-auto-repair-functions-dev \\"
echo "  --template-body file://lambda-auto-repair-functions.yaml \\"
echo "  --parameters ParameterKey=Environment,ParameterValue=dev \\"
echo "               ParameterKey=MainStackName,ParameterValue=lambda-auto-repair-main-dev \\"
echo "  --capabilities CAPABILITY_NAMED_IAM"
echo ""
echo "# Deploy monitoring stack"
echo "aws cloudformation create-stack \\"
echo "  --stack-name lambda-auto-repair-monitoring-dev \\"
echo "  --template-body file://lambda-auto-repair-monitoring.yaml \\"
echo "  --parameters ParameterKey=Environment,ParameterValue=dev \\"
echo "               ParameterKey=MainStackName,ParameterValue=lambda-auto-repair-main-dev"
echo ""

echo "=== Post-Deployment Steps ==="
echo "1. Configure Bedrock Knowledge Base with Lambda troubleshooting documents"
echo "2. Add target Lambda functions to monitor"
echo "3. Test the system with sample CloudWatch alarms"
echo "4. Review and customize alarm thresholds"
echo "5. Set up additional notification channels if needed"
echo ""

echo "=== Cleanup ==="
echo "To remove all resources:"
echo "aws cloudformation delete-stack --stack-name lambda-auto-repair-monitoring-dev"
echo "aws cloudformation delete-stack --stack-name lambda-auto-repair-functions-dev"
echo "aws cloudformation delete-stack --stack-name lambda-auto-repair-main-dev"