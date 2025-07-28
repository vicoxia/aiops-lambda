# Lambda Auto-Repair System - 操作手册

## 概述

本操作手册为 Lambda 自动修复系统的日常运维提供详细指导。系统通过监控 Lambda 函数性能异常，自动诊断问题原因，并执行相应的修复操作。

## 系统架构概览

```
CloudWatch告警 → EventBridge → Step Functions状态机 → Lambda函数编排 → 结果通知
```

### 核心组件

1. **监控子系统**: CloudWatch 指标收集和告警
2. **事件处理**: EventBridge 事件路由触发 Step Functions 工作流
3. **工作流编排**: Step Functions 状态机协调整个修复流程
4. **智能诊断**: Bedrock Agent 和 Knowledge Base 进行问题分析
5. **自动修复**: Lambda 函数配置修改和验证
6. **结果通知**: SNS 发送修复结果通知

### Step Functions 工作流步骤

1. **ParseAlarmEvent** - 解析和验证 CloudWatch 告警事件
2. **CollectMetricsAndLogs** - 收集目标函数的性能指标和日志
3. **DiagnoseIssue** - 使用 AI 分析问题并提供修复建议
4. **DetermineAction** - 基于诊断结果决定修复策略
5. **ExecuteRepair** - 执行 Lambda 函数配置修改
6. **VerifyRepair** - 验证修复效果和函数健康状态
7. **NotifyResult** - 发送修复结果和状态通知

## 日常运维任务

### 1. 系统健康检查

#### 每日检查清单

```bash
# 1. 检查系统整体状态
./validate-deployment.sh --environment prod

# 2. 检查 CloudWatch 仪表板
# 访问: https://console.aws.amazon.com/cloudwatch/home#dashboards:name=lambda-auto-repair-prod

# 3. 检查最近的修复操作
aws dynamodb scan \
  --table-name lambda-auto-repair-repairs-prod \
  --filter-expression "executedAt > :yesterday" \
  --expression-attribute-values '{":yesterday":{"S":"2024-01-01T00:00:00Z"}}'

# 4. 检查系统告警状态
aws cloudwatch describe-alarms \
  --alarm-names "lambda-auto-repair-system-health-prod" \
  --query 'MetricAlarms[0].StateValue'
```

#### 每周检查清单

```bash
# 1. 检查 Lambda 函数性能
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=lambda-auto-repair-coordinator-prod \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-08T00:00:00Z \
  --period 86400 \
  --statistics Average,Maximum

# 2. 检查 DynamoDB 表使用情况
aws dynamodb describe-table \
  --table-name lambda-auto-repair-diagnosis-prod \
  --query 'Table.{ItemCount:ItemCount,TableSizeBytes:TableSizeBytes}'

# 3. 检查 Step Functions 执行统计
aws stepfunctions describe-state-machine \
  --state-machine-arn "arn:aws:states:us-east-1:ACCOUNT:stateMachine:lambda-auto-repair-workflow-prod" \
  --query 'status'

# 4. 检查知识库更新状态
aws bedrock-agent get-knowledge-base \
  --knowledge-base-id "kb-1234567890abcdef" \
  --query 'knowledgeBase.status'
```

### 2. 监控和告警管理

#### 查看当前告警状态

```bash
# 查看所有系统相关告警
aws cloudwatch describe-alarms \
  --alarm-name-prefix "lambda-auto-repair" \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Reason:StateReason}'

# 查看告警历史
aws cloudwatch describe-alarm-history \
  --alarm-name "lambda-auto-repair-system-health-prod" \
  --max-records 10
```

#### 调整告警阈值

```bash
# 修改 Lambda 持续时间告警阈值
aws cloudwatch put-metric-alarm \
  --alarm-name "lambda-duration-alarm-my-function" \
  --alarm-description "Lambda function duration alarm" \
  --metric-name Duration \
  --namespace AWS/Lambda \
  --statistic Average \
  --period 300 \
  --threshold 35000 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=my-target-function \
  --evaluation-periods 2
```

#### 添加新的监控目标

```bash
# 为新的 Lambda 函数创建监控告警
aws cloudwatch put-metric-alarm \
  --alarm-name "lambda-duration-alarm-new-function" \
  --alarm-description "Monitor new Lambda function performance" \
  --metric-name Duration \
  --namespace AWS/Lambda \
  --statistic Average \
  --period 300 \
  --threshold 30000 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=new-target-function \
  --evaluation-periods 2 \
  --alarm-actions "arn:aws:sns:us-east-1:ACCOUNT:lambda-auto-repair-notifications-prod"
```

### 3. 修复操作管理

#### 查看修复历史

```bash
# 查看最近的修复操作
aws dynamodb scan \
  --table-name lambda-auto-repair-repairs-prod \
  --limit 10 \
  --query 'Items[].{Function:functionName.S,Status:status.S,Time:executedAt.S,Memory:newMemory.N}'

# 查看特定函数的修复历史
aws dynamodb query \
  --table-name lambda-auto-repair-repairs-prod \
  --key-condition-expression "functionName = :fn" \
  --expression-attribute-values '{":fn":{"S":"my-target-function"}}'
```

#### 手动触发修复流程

```bash
# 手动触发诊断和修复流程
aws stepfunctions start-execution \
  --state-machine-arn "arn:aws:states:us-east-1:ACCOUNT:stateMachine:lambda-auto-repair-workflow-prod" \
  --input '{
    "functionName": "my-target-function",
    "alarmName": "lambda-duration-alarm-my-target-function",
    "manual": true
  }'

# 查看执行状态
aws stepfunctions describe-execution \
  --execution-arn "arn:aws:states:us-east-1:ACCOUNT:execution:lambda-auto-repair-workflow-prod:execution-id"
```

#### 暂停自动修复

```bash
# 禁用特定函数的自动修复
aws events disable-rule \
  --name "lambda-auto-repair-alarm-rule-my-function" \
  --event-bus-name "lambda-auto-repair-prod"

# 重新启用自动修复
aws events enable-rule \
  --name "lambda-auto-repair-alarm-rule-my-function" \
  --event-bus-name "lambda-auto-repair-prod"
```

### 4. 知识库管理

#### 更新知识库内容

```bash
# 上传新的故障排除文档
aws s3 cp troubleshooting-guide.md s3://lambda-auto-repair-knowledge-bucket-prod/

# 同步知识库
aws bedrock-agent start-ingestion-job \
  --knowledge-base-id "kb-1234567890abcdef" \
  --data-source-id "ds-1234567890abcdef"

# 检查同步状态
aws bedrock-agent get-ingestion-job \
  --knowledge-base-id "kb-1234567890abcdef" \
  --data-source-id "ds-1234567890abcdef" \
  --ingestion-job-id "job-1234567890abcdef"
```

#### 测试知识库查询

```bash
# 测试知识库检索功能
aws bedrock-agent-runtime retrieve \
  --knowledge-base-id "kb-1234567890abcdef" \
  --retrieval-query '{
    "text": "Lambda function memory exhaustion timeout"
  }'
```

### 5. 通知管理

#### 管理 SNS 订阅

```bash
# 查看当前订阅
aws sns list-subscriptions-by-topic \
  --topic-arn "arn:aws:sns:us-east-1:ACCOUNT:lambda-auto-repair-notifications-prod"

# 添加新的邮件订阅
aws sns subscribe \
  --topic-arn "arn:aws:sns:us-east-1:ACCOUNT:lambda-auto-repair-notifications-prod" \
  --protocol email \
  --notification-endpoint new-admin@example.com

# 添加 Slack 集成（通过 Lambda）
aws sns subscribe \
  --topic-arn "arn:aws:sns:us-east-1:ACCOUNT:lambda-auto-repair-notifications-prod" \
  --protocol lambda \
  --notification-endpoint "arn:aws:lambda:us-east-1:ACCOUNT:function:slack-notifier"
```

#### 自定义通知内容

```bash
# 更新通知模板（通过环境变量）
aws lambda update-function-configuration \
  --function-name lambda-auto-repair-verifier-prod \
  --environment Variables='{
    "NOTIFICATION_TEMPLATE": "custom",
    "SLACK_WEBHOOK_URL": "https://hooks.slack.com/services/...",
    "EMAIL_TEMPLATE": "detailed"
  }'
```

## 性能优化

### 1. Lambda 函数优化

#### 监控函数性能

```bash
# 查看函数执行统计
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=lambda-auto-repair-coordinator-prod \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Average,Maximum,Minimum

# 查看内存使用情况
aws logs filter-log-events \
  --log-group-name "/aws/lambda/lambda-auto-repair-coordinator-prod" \
  --filter-pattern "REPORT" \
  --limit 10
```

#### 调整函数配置

```bash
# 增加函数内存配置
aws lambda update-function-configuration \
  --function-name lambda-auto-repair-coordinator-prod \
  --memory-size 512

# 调整超时时间
aws lambda update-function-configuration \
  --function-name lambda-auto-repair-coordinator-prod \
  --timeout 300
```

### 2. DynamoDB 优化

#### 监控表性能

```bash
# 查看表指标
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedReadCapacityUnits \
  --dimensions Name=TableName,Value=lambda-auto-repair-repairs-prod \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum

# 检查热分区
aws dynamodb describe-table \
  --table-name lambda-auto-repair-repairs-prod \
  --query 'Table.GlobalSecondaryIndexes[].{IndexName:IndexName,Status:IndexStatus}'
```

#### 优化表配置

```bash
# 启用按需计费（如果适用）
aws dynamodb modify-table \
  --table-name lambda-auto-repair-repairs-prod \
  --billing-mode PAY_PER_REQUEST

# 启用时间点恢复
aws dynamodb put-backup-policy \
  --table-name lambda-auto-repair-repairs-prod \
  --backup-policy PointInTimeRecoveryEnabled=true
```

### 3. Step Functions 优化

#### 监控工作流性能

```bash
# 查看执行统计
aws stepfunctions list-executions \
  --state-machine-arn "arn:aws:states:us-east-1:ACCOUNT:stateMachine:lambda-auto-repair-workflow-prod" \
  --status-filter SUCCEEDED \
  --max-items 10

# 分析执行时间
aws stepfunctions describe-execution \
  --execution-arn "arn:aws:states:us-east-1:ACCOUNT:execution:lambda-auto-repair-workflow-prod:execution-id" \
  --query '{StartDate:startDate,StopDate:stopDate,Status:status}'
```

## 安全管理

### 1. IAM 权限审计

#### 定期权限检查

```bash
# 检查系统角色权限
aws iam get-role-policy \
  --role-name lambda-auto-repair-execution-prod \
  --policy-name lambda-auto-repair-policy

# 检查最后使用时间
aws iam get-role \
  --role-name lambda-auto-repair-execution-prod \
  --query 'Role.RoleLastUsed'

# 生成权限报告
aws iam generate-service-last-accessed-details \
  --arn "arn:aws:iam::ACCOUNT:role/lambda-auto-repair-execution-prod"
```

#### 权限最小化

```bash
# 检查未使用的权限
aws iam get-service-last-accessed-details \
  --job-id "job-id-from-previous-command"

# 更新角色权限（移除未使用的权限）
aws iam put-role-policy \
  --role-name lambda-auto-repair-execution-prod \
  --policy-name lambda-auto-repair-policy \
  --policy-document file://updated-policy.json
```

### 2. 加密管理

#### KMS 密钥管理

```bash
# 检查密钥使用情况
aws kms describe-key \
  --key-id "arn:aws:kms:us-east-1:ACCOUNT:key/key-id" \
  --query 'KeyMetadata.{KeyUsage:KeyUsage,KeyState:KeyState}'

# 轮换密钥
aws kms enable-key-rotation \
  --key-id "arn:aws:kms:us-east-1:ACCOUNT:key/key-id"

# 检查轮换状态
aws kms get-key-rotation-status \
  --key-id "arn:aws:kms:us-east-1:ACCOUNT:key/key-id"
```

### 3. 审计日志

#### 查看操作审计

```bash
# 查看最近的修复操作审计
aws dynamodb scan \
  --table-name lambda-auto-repair-diagnosis-prod \
  --filter-expression "executedAt > :yesterday" \
  --expression-attribute-values '{":yesterday":{"S":"2024-01-01T00:00:00Z"}}' \
  --projection-expression "functionName, diagnosisResult, executedAt, executedBy"

# 查看 CloudTrail 日志
aws logs filter-log-events \
  --log-group-name "CloudTrail/lambda-auto-repair" \
  --filter-pattern "{ $.eventName = UpdateFunctionConfiguration }" \
  --start-time 1640995200000
```

## 备份和恢复

### 1. 数据备份

#### DynamoDB 备份

```bash
# 创建按需备份
aws dynamodb create-backup \
  --table-name lambda-auto-repair-repairs-prod \
  --backup-name "lambda-auto-repair-repairs-backup-$(date +%Y%m%d)"

# 列出现有备份
aws dynamodb list-backups \
  --table-name lambda-auto-repair-repairs-prod

# 从备份恢复表
aws dynamodb restore-table-from-backup \
  --target-table-name lambda-auto-repair-repairs-prod-restored \
  --backup-arn "arn:aws:dynamodb:us-east-1:ACCOUNT:table/lambda-auto-repair-repairs-prod/backup/backup-id"
```

#### 配置备份

```bash
# 导出 CloudFormation 模板
aws cloudformation get-template \
  --stack-name lambda-auto-repair-main-prod \
  --template-stage Processed > backup-template.json

# 备份参数文件
cp parameters/prod.json backup/parameters-prod-$(date +%Y%m%d).json
```

### 2. 灾难恢复

#### 跨区域复制

```bash
# 在备用区域部署系统
./deploy.sh \
  --environment prod-dr \
  --region us-west-2 \
  --email ops-team@example.com \
  --enable-approval

# 同步 DynamoDB 数据（使用 DynamoDB Global Tables）
aws dynamodb create-global-table \
  --global-table-name lambda-auto-repair-repairs-prod \
  --replication-group RegionName=us-east-1 RegionName=us-west-2
```

## 成本管理

### 1. 成本监控

#### 查看服务成本

```bash
# 查看 Lambda 成本
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --filter '{
    "Dimensions": {
      "Key": "SERVICE",
      "Values": ["Amazon Elastic Compute Cloud - Compute"]
    }
  }'

# 查看 DynamoDB 成本
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --filter '{
    "Dimensions": {
      "Key": "SERVICE",
      "Values": ["Amazon DynamoDB"]
    }
  }'
```

#### 设置成本告警

```bash
# 创建成本预算
aws budgets create-budget \
  --account-id ACCOUNT-ID \
  --budget '{
    "BudgetName": "lambda-auto-repair-monthly-budget",
    "BudgetLimit": {
      "Amount": "100",
      "Unit": "USD"
    },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST",
    "CostFilters": {
      "TagKey": ["Project"],
      "TagValue": ["lambda-auto-repair"]
    }
  }'
```

### 2. 成本优化

#### 优化 Lambda 配置

```bash
# 分析 Lambda 函数成本效率
aws logs filter-log-events \
  --log-group-name "/aws/lambda/lambda-auto-repair-coordinator-prod" \
  --filter-pattern "REPORT" \
  --start-time 1640995200000 \
  --limit 100 | jq '.events[].message' | grep -E "(Duration|Billed Duration|Memory Size|Max Memory Used)"
```

#### 清理未使用资源

```bash
# 查找未使用的 CloudWatch 日志组
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/lambda/lambda-auto-repair" \
  --query 'logGroups[?!lastEventTime || lastEventTime < `1640995200000`].logGroupName'

# 删除旧的日志组
aws logs delete-log-group \
  --log-group-name "/aws/lambda/old-function-name"
```

## 故障处理流程

### 1. 告警响应流程

1. **接收告警** - 通过 SNS、邮件或 Slack 接收系统告警
2. **初步评估** - 检查告警严重程度和影响范围
3. **系统检查** - 运行健康检查脚本验证系统状态
4. **问题定位** - 查看相关日志和指标确定问题原因
5. **采取行动** - 根据问题类型执行相应的修复操作
6. **验证修复** - 确认问题已解决，系统恢复正常
7. **记录总结** - 记录问题和解决方案，更新知识库

### 2. 升级流程

当自动修复无法解决问题时：

1. **人工介入** - 系统管理员接管处理
2. **深度分析** - 详细分析日志、指标和系统状态
3. **专家咨询** - 必要时咨询 AWS 技术支持或内部专家
4. **手动修复** - 执行手动修复操作
5. **系统更新** - 更新自动修复逻辑和知识库
6. **流程改进** - 优化监控和告警机制

## 联系信息

### 支持团队

- **一级支持**: ops-team@example.com
- **二级支持**: platform-team@example.com
- **紧急联系**: on-call-engineer@example.com

### 相关文档

- [部署指南](deployment-guide.md)
- [故障排除指南](troubleshooting-guide.md)
- [系统架构文档](../README.md)
- [AWS 官方文档](https://docs.aws.amazon.com/)

---

**注意**: 本操作手册应定期更新，确保与系统实际配置保持一致。建议每季度审查一次操作流程和最佳实践。