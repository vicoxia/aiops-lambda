# Lambda Auto-Repair System - 部署指南

## 概述

本指南详细介绍了如何部署 Lambda 自动修复系统。该系统采用 AWS CloudFormation 进行基础设施即代码（IaC）部署，包含监控、诊断、修复和通知等完整功能。

## 系统架构

Lambda 自动修复系统采用 **Step Functions 工作流架构**，由以下三个主要 CloudFormation 堆栈组成：

1. **主基础设施堆栈** (`lambda-auto-repair-main.yaml`)
   - 核心资源：S3、KMS、SNS、EventBridge、DynamoDB
   - 提供系统运行的基础设施支撑

2. **函数和工作流堆栈** (`lambda-auto-repair-functions.yaml`)
   - Lambda 函数、Step Functions 状态机、EventBridge 规则
   - 实现系统的核心业务逻辑和工作流编排

3. **监控和告警堆栈** (`lambda-auto-repair-monitoring.yaml`)
   - CloudWatch 仪表板、告警、自定义指标
   - 提供系统可观测性和监控能力

### 工作流程

```
CloudWatch 告警 → EventBridge → Step Functions 状态机 → Lambda 函数编排
```

**Step Functions 工作流步骤：**
1. **ParseAlarmEvent** - 解析 CloudWatch 告警事件
2. **CollectMetricsAndLogs** - 收集函数指标和日志数据
3. **DiagnoseIssue** - 使用 Bedrock 智能诊断问题
4. **DetermineAction** - 决定是否需要执行修复
5. **ExecuteRepair** - 执行 Lambda 函数配置修复
6. **VerifyRepair** - 验证修复效果
7. **NotifyResult** - 发送修复结果通知

## 部署前准备

### 1. 环境要求

- **AWS CLI**: 版本 2.0 或更高
- **jq**: JSON 处理工具（用于验证脚本）
- **Bash**: Shell 环境（Linux/macOS/WSL）
- **AWS 账户**: 具有适当权限的 AWS 账户

### 2. AWS 权限要求

部署账户需要以下 AWS 服务权限：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:*",
        "iam:*",
        "lambda:*",
        "states:*",
        "events:*",
        "cloudwatch:*",
        "sns:*",
        "dynamodb:*",
        "s3:*",
        "kms:*",
        "bedrock:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### 3. 配置 AWS CLI

```bash
# 配置 AWS 凭证
aws configure

# 验证配置
aws sts get-caller-identity
```

### 4. 准备部署参数

根据目标环境编辑相应的参数文件：

- `parameters/dev.json` - 开发环境
- `parameters/staging.json` - 测试环境
- `parameters/prod.json` - 生产环境

## 部署步骤

### 方法一：使用自动化部署脚本（推荐）

#### 1. 开发环境部署

```bash
# 基本部署
./deploy.sh --environment dev --email dev-team@example.com

# 验证部署
./validate-deployment.sh --environment dev
```

#### 2. 测试环境部署

```bash
# 启用审批工作流的部署
./deploy.sh \
  --environment staging \
  --email staging-team@example.com \
  --enable-approval

# 验证部署
./validate-deployment.sh --environment staging
```

#### 3. 生产环境部署

```bash
# 完整配置的生产环境部署
./deploy.sh \
  --environment prod \
  --email ops-team@example.com \
  --enable-approval \
  --knowledge-base-id kb-1234567890abcdef \
  --region us-west-2

# 验证部署
./validate-deployment.sh --environment prod --region us-west-2
```

#### 4. 模板验证（干运行）

```bash
# 仅验证模板，不实际部署
./deploy.sh --environment dev --email test@example.com --dry-run
```

### 方法二：手动 CloudFormation 部署

#### 1. 验证模板

```bash
# 验证所有模板
aws cloudformation validate-template --template-body file://lambda-auto-repair-main.yaml
aws cloudformation validate-template --template-body file://lambda-auto-repair-functions.yaml
aws cloudformation validate-template --template-body file://lambda-auto-repair-monitoring.yaml
```

#### 2. 部署主基础设施堆栈

```bash
aws cloudformation create-stack \
  --stack-name lambda-auto-repair-main-dev \
  --template-body file://lambda-auto-repair-main.yaml \
  --parameters ParameterKey=Environment,ParameterValue=dev \
               ParameterKey=NotificationEmail,ParameterValue=admin@example.com \
               ParameterKey=EnableApprovalWorkflow,ParameterValue=false \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# 等待堆栈创建完成
aws cloudformation wait stack-create-complete \
  --stack-name lambda-auto-repair-main-dev \
  --region us-east-1
```

#### 3. 部署函数堆栈

```bash
aws cloudformation create-stack \
  --stack-name lambda-auto-repair-functions-dev \
  --template-body file://lambda-auto-repair-functions.yaml \
  --parameters ParameterKey=Environment,ParameterValue=dev \
               ParameterKey=MainStackName,ParameterValue=lambda-auto-repair-main-dev \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# 等待堆栈创建完成
aws cloudformation wait stack-create-complete \
  --stack-name lambda-auto-repair-functions-dev \
  --region us-east-1
```

#### 4. 部署监控堆栈

```bash
aws cloudformation create-stack \
  --stack-name lambda-auto-repair-monitoring-dev \
  --template-body file://lambda-auto-repair-monitoring.yaml \
  --parameters ParameterKey=Environment,ParameterValue=dev \
               ParameterKey=MainStackName,ParameterValue=lambda-auto-repair-main-dev \
  --region us-east-1

# 等待堆栈创建完成
aws cloudformation wait stack-create-complete \
  --stack-name lambda-auto-repair-monitoring-dev \
  --region us-east-1
```

## 部署后配置

### 1. 配置 Bedrock Knowledge Base

```bash
# 创建知识库（如果尚未存在）
aws bedrock-agent create-knowledge-base \
  --name "lambda-performance-kb-dev" \
  --description "Lambda 性能问题诊断知识库" \
  --role-arn "arn:aws:iam::ACCOUNT:role/BedrockKnowledgeBaseRole"

# 上传知识文档
aws bedrock-agent create-data-source \
  --knowledge-base-id "kb-1234567890abcdef" \
  --name "lambda-troubleshooting-docs" \
  --data-source-configuration '{
    "type": "S3",
    "s3Configuration": {
      "bucketArn": "arn:aws:s3:::your-knowledge-bucket"
    }
  }'
```

### 2. 添加监控目标函数

编辑 CloudFormation 模板或使用 AWS CLI 添加要监控的 Lambda 函数：

```bash
# 为目标函数创建 CloudWatch 告警
aws cloudwatch put-metric-alarm \
  --alarm-name "lambda-duration-alarm-my-function" \
  --alarm-description "Lambda function duration alarm" \
  --metric-name Duration \
  --namespace AWS/Lambda \
  --statistic Average \
  --period 300 \
  --threshold 30000 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=my-target-function \
  --evaluation-periods 2 \
  --alarm-actions "arn:aws:sns:us-east-1:ACCOUNT:lambda-auto-repair-notifications-dev"
```

### 3. 测试系统功能

```bash
# 触发测试告警
aws cloudwatch set-alarm-state \
  --alarm-name "lambda-duration-alarm-my-function" \
  --state-value ALARM \
  --state-reason "Testing auto-repair system"

# 检查 Step Functions 执行
aws stepfunctions list-executions \
  --state-machine-arn "arn:aws:states:us-east-1:ACCOUNT:stateMachine:lambda-auto-repair-workflow-dev"
```

## 环境特定配置

### 开发环境 (dev)

```json
{
  "DurationThreshold": 45000,
  "ErrorThreshold": 2,
  "TimeoutThreshold": 2,
  "EnableApprovalWorkflow": false,
  "LogRetentionDays": 7
}
```

**特点：**
- 较宽松的告警阈值
- 无需人工审批
- 较短的日志保留期
- 成本优化配置

### 测试环境 (staging)

```json
{
  "DurationThreshold": 35000,
  "ErrorThreshold": 1,
  "TimeoutThreshold": 1,
  "EnableApprovalWorkflow": true,
  "LogRetentionDays": 14
}
```

**特点：**
- 中等告警阈值
- 启用人工审批流程
- 中等日志保留期
- 接近生产环境配置

### 生产环境 (prod)

```json
{
  "DurationThreshold": 30000,
  "ErrorThreshold": 1,
  "TimeoutThreshold": 1,
  "EnableApprovalWorkflow": true,
  "LogRetentionDays": 30,
  "BackupEnabled": true
}
```

**特点：**
- 严格的告警阈值
- 强制人工审批
- 长期日志保留
- 启用备份和高可用性

## 部署验证

### 1. 使用验证脚本

```bash
# 完整验证
./validate-deployment.sh --environment prod --region us-west-2

# 验证输出示例
=== Lambda Auto-Repair System Validation ===
Environment: prod
Region: us-west-2
=============================================
Checking stack: lambda-auto-repair-main-prod
  Status: CREATE_COMPLETE
  ✅ Stack is healthy
Checking stack: lambda-auto-repair-functions-prod
  Status: CREATE_COMPLETE
  ✅ Stack is healthy
Validating Lambda functions...
  ✅ All functions are active
Validating Step Functions...
  ✅ State machine is active
```

### 2. 手动验证检查项

#### 检查堆栈状态

```bash
aws cloudformation describe-stacks \
  --stack-name lambda-auto-repair-main-prod \
  --query 'Stacks[0].StackStatus'
```

#### 检查 Lambda 函数

```bash
aws lambda list-functions \
  --query 'Functions[?contains(FunctionName, `lambda-auto-repair`)].{Name:FunctionName,State:State}'
```

#### 检查 Step Functions

```bash
aws stepfunctions list-state-machines \
  --query 'stateMachines[?contains(name, `lambda-auto-repair`)].{Name:name,Status:status}'
```

#### 检查 EventBridge

```bash
aws events list-event-buses \
  --query 'EventBuses[?contains(Name, `lambda-auto-repair`)].Name'
```

#### 检查 DynamoDB 表

```bash
aws dynamodb list-tables \
  --query 'TableNames[?contains(@, `lambda-auto-repair`)]'
```

## 更新和维护

### 1. 更新部署

```bash
# 更新现有部署
./deploy.sh --environment prod --email ops-team@example.com --enable-approval

# 脚本会自动检测现有堆栈并执行更新操作
```

### 2. 回滚部署

```bash
# 查看堆栈历史
aws cloudformation list-stack-resources --stack-name lambda-auto-repair-main-prod

# 回滚到上一个版本
aws cloudformation cancel-update-stack --stack-name lambda-auto-repair-main-prod
```

### 3. 监控部署状态

```bash
# 实时监控堆栈事件
aws cloudformation describe-stack-events \
  --stack-name lambda-auto-repair-main-prod \
  --query 'StackEvents[0:10].{Time:Timestamp,Status:ResourceStatus,Reason:ResourceStatusReason}'
```

## 清理和卸载

### 1. 完整清理

```bash
# 按相反顺序删除堆栈
aws cloudformation delete-stack --stack-name lambda-auto-repair-monitoring-prod
aws cloudformation delete-stack --stack-name lambda-auto-repair-functions-prod
aws cloudformation delete-stack --stack-name lambda-auto-repair-main-prod

# 等待删除完成
aws cloudformation wait stack-delete-complete --stack-name lambda-auto-repair-monitoring-prod
aws cloudformation wait stack-delete-complete --stack-name lambda-auto-repair-functions-prod
aws cloudformation wait stack-delete-complete --stack-name lambda-auto-repair-main-prod
```

### 2. 清理残留资源

```bash
# 检查并清理 S3 存储桶
aws s3 ls | grep lambda-auto-repair
aws s3 rb s3://lambda-auto-repair-deployment-bucket-prod --force

# 检查并清理 CloudWatch 日志组
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/lambda-auto-repair"
```

## 故障排除

### 1. 部署失败

```bash
# 查看失败原因
aws cloudformation describe-stack-events \
  --stack-name lambda-auto-repair-main-prod \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

### 2. 权限问题

```bash
# 检查当前用户权限
aws iam get-user
aws sts get-caller-identity

# 检查角色权限
aws iam get-role --role-name lambda-auto-repair-execution-prod
```

### 3. 资源限制

```bash
# 检查服务限制
aws service-quotas get-service-quota \
  --service-code lambda \
  --quota-code L-B99A9384  # Concurrent executions
```

## 最佳实践

### 1. 部署策略

- **渐进式部署**: 先部署到开发环境，然后测试环境，最后生产环境
- **蓝绿部署**: 对于关键更新，考虑使用蓝绿部署策略
- **回滚计划**: 每次部署前准备回滚计划

### 2. 安全考虑

- **最小权限**: 使用最小必要权限的 IAM 角色
- **加密**: 启用传输和存储加密
- **审计**: 启用 CloudTrail 记录所有 API 调用

### 3. 成本优化

- **资源标记**: 为所有资源添加适当的标签
- **监控成本**: 设置成本告警和预算
- **定期清理**: 定期清理未使用的资源

### 4. 监控和告警

- **健康检查**: 设置系统健康检查告警
- **性能监控**: 监控关键性能指标
- **日志聚合**: 集中收集和分析日志

## 支持和联系

如遇到部署问题，请：

1. 检查 CloudFormation 堆栈事件日志
2. 查看 Lambda 函数日志
3. 运行验证脚本诊断问题
4. 参考故障排除指南
5. 联系系统管理员或开发团队

---

**注意**: 本指南假设您具有 AWS 服务的基本知识。如需更详细的 AWS 服务文档，请参考 [AWS 官方文档](https://docs.aws.amazon.com/)。