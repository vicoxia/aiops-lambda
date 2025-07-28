# Lambda Auto-Repair System - Infrastructure as Code

This directory contains the Infrastructure as Code (IaC) templates and deployment scripts for the Lambda Auto-Repair System.

## Overview

The Lambda Auto-Repair System is deployed using AWS CloudFormation templates organized into three main stacks:

1. **Main Infrastructure** (`lambda-auto-repair-main.yaml`) - Core resources like S3, KMS, SNS, EventBridge, and DynamoDB
2. **Functions and Workflows** (`lambda-auto-repair-functions.yaml`) - Lambda functions, Step Functions, and EventBridge rules
3. **Monitoring and Alarms** (`lambda-auto-repair-monitoring.yaml`) - CloudWatch dashboards, alarms, and custom metrics

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   CloudWatch    │    │   EventBridge   │    │ Step Functions  │
│     Alarms      │───▶│   Event Bus     │───▶│   Workflow      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Event Parser  │    │ Data Collector  │    │   Diagnosis     │
│   (Adapter)     │───▶│   Function      │───▶│   Function      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Verification   │◀───│ Repair Executor │◀───│ Action Decision │
│   Function      │    │   Function      │    │   (Choice)      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│      SNS        │    │   DynamoDB      │    │   CloudWatch    │
│ Notifications   │    │   Audit Logs    │    │   Monitoring    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Prerequisites

- AWS CLI configured with appropriate permissions
- jq (for JSON processing in validation scripts)
- Bash shell environment

### Required AWS Permissions

The deployment requires the following AWS permissions:

- CloudFormation: Full access for stack management
- IAM: Create and manage roles and policies
- Lambda: Create and manage functions
- Step Functions: Create and manage state machines
- EventBridge: Create and manage event buses and rules
- CloudWatch: Create and manage alarms, dashboards, and log groups
- SNS: Create and manage topics and subscriptions
- DynamoDB: Create and manage tables
- S3: Create and manage buckets
- KMS: Create and manage encryption keys
- Bedrock: Access to models and knowledge bases

## Quick Start

### 1. Deploy to Development Environment

```bash
./deploy.sh --environment dev --email your-email@example.com
```

### 2. Deploy to Production Environment

```bash
./deploy.sh --environment prod --email ops-team@example.com --enable-approval
```

### 3. Validate Deployment

```bash
./validate-deployment.sh --environment dev
```

## Deployment Options

### Basic Deployment

```bash
./deploy.sh --environment dev --email admin@example.com
```

### Production Deployment with Approval Workflow

```bash
./deploy.sh \
  --environment prod \
  --email ops-team@example.com \
  --enable-approval \
  --knowledge-base-id your-kb-id \
  --region us-west-2
```

### Dry Run (Validation Only)

```bash
./deploy.sh --environment staging --email test@example.com --dry-run
```

## Configuration

### Environment-Specific Parameters

Each environment has its own parameter file in the `parameters/` directory:

- `dev.json` - Development environment settings
- `staging.json` - Staging environment settings  
- `prod.json` - Production environment settings

### Key Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `Environment` | Deployment environment | `dev` |
| `NotificationEmail` | Email for system notifications | Required |
| `EnableApprovalWorkflow` | Enable manual approval for repairs | `false` |
| `BedrockModelId` | Bedrock model for diagnosis | `anthropic.claude-3-sonnet-20240229-v1:0` |
| `DurationThreshold` | Lambda duration alarm threshold (ms) | `30000` |
| `ErrorThreshold` | Error count threshold | `1` |
| `TimeoutThreshold` | Timeout count threshold | `1` |

## Stack Details

### Main Infrastructure Stack

**Resources Created:**
- S3 bucket for deployment artifacts
- KMS key for encryption
- SNS topic for notifications
- EventBridge custom event bus
- DynamoDB tables for audit logging

**Outputs:**
- Deployment bucket name
- Encryption key ID
- Notification topic ARN
- Event bus ARN
- DynamoDB table names

### Functions and Workflows Stack

**Resources Created:**
- Lambda functions for each system component
- IAM roles with least-privilege permissions
- Step Functions state machine for complex workflows
- EventBridge rules for event routing
- CloudWatch alarms for system monitoring

**Lambda Functions:**
- `data-collector` - Collects metrics and logs from CloudWatch
- `diagnosis` - Performs intelligent diagnosis using Bedrock
- `executor` - Executes repair actions on Lambda functions
- `verifier` - Verifies repair effectiveness
- `coordinator` - Coordinates simple workflows

### Monitoring and Alarms Stack

**Resources Created:**
- CloudWatch dashboard for system visibility
- Composite alarms for system health monitoring
- Custom metric filters for tracking repair actions
- Log groups with encryption and retention policies

## Security Features

### Encryption
- All data encrypted in transit and at rest
- KMS keys for encryption with proper key policies
- Lambda environment variables encrypted

### IAM Security
- Least-privilege IAM roles for each component
- Service-specific permissions with resource restrictions
- Cross-service access properly configured

### Audit and Compliance
- Comprehensive audit logging in DynamoDB
- CloudTrail integration for API call tracking
- Detailed operation records with timestamps

## Monitoring and Alerting

### CloudWatch Dashboard

The system creates a comprehensive dashboard showing:
- Lambda function metrics (invocations, errors, duration)
- Step Functions execution statistics
- Recent system logs
- Custom metrics for repair actions

### Alarms

**System Health Alarms:**
- Lambda function errors
- Step Functions execution failures
- High frequency of repair actions
- System component availability

**Composite Alarms:**
- Overall system health status
- Escalation triggers for critical issues

### Custom Metrics

- `RepairActionsExecuted` - Count of repair actions performed
- `DiagnosisCompleted` - Count of diagnosis operations completed
- Custom dimensions for function names and environments

## Troubleshooting

### Common Issues

1. **Stack Creation Fails**
   ```bash
   # Check stack events
   aws cloudformation describe-stack-events --stack-name lambda-auto-repair-main-dev
   ```

2. **Lambda Function Errors**
   ```bash
   # Check function logs
   aws logs tail /aws/lambda/lambda-auto-repair-coordinator-dev --follow
   ```

3. **Permission Issues**
   ```bash
   # Validate IAM roles
   aws iam get-role --role-name lambda-auto-repair-execution-dev
   ```

### Validation Commands

```bash
# Validate all templates
aws cloudformation validate-template --template-body file://lambda-auto-repair-main.yaml

# Check stack status
aws cloudformation describe-stacks --stack-name lambda-auto-repair-main-dev

# Test Lambda function
aws lambda invoke --function-name lambda-auto-repair-coordinator-dev --payload '{}' response.json
```

## Cleanup

To remove all resources:

```bash
# Delete stacks in reverse order
aws cloudformation delete-stack --stack-name lambda-auto-repair-monitoring-dev
aws cloudformation delete-stack --stack-name lambda-auto-repair-functions-dev
aws cloudformation delete-stack --stack-name lambda-auto-repair-main-dev
```

## Cost Optimization

### Development Environment
- Shorter log retention (7 days)
- Lower alarm thresholds
- Reduced Lambda memory allocations

### Production Environment
- Longer log retention (30 days)
- Stricter alarm thresholds
- Point-in-time recovery for DynamoDB
- Enhanced monitoring and alerting

## Next Steps

After successful deployment:

1. **Configure Bedrock Knowledge Base**
   - Upload Lambda performance troubleshooting documents
   - Configure knowledge base retrieval settings

2. **Add Target Functions**
   - Identify Lambda functions to monitor
   - Configure appropriate alarm thresholds
   - Test with sample alarms

3. **Customize Workflows**
   - Adjust Step Functions workflow for specific needs
   - Configure approval processes for production
   - Set up additional notification channels

4. **Monitor and Tune**
   - Review CloudWatch dashboard regularly
   - Adjust alarm thresholds based on baseline metrics
   - Optimize Lambda function configurations

## Support

For issues and questions:
- Check CloudWatch logs for detailed error information
- Use the validation script to verify system health
- Review CloudFormation stack events for deployment issues
- Consult the main project documentation for system behavior