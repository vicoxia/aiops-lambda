# Lambda Auto-Repair System - 故障排除指南

## 概述

本指南提供 Lambda 自动修复系统常见问题的诊断和解决方案。按照问题类型分类，提供详细的排查步骤和修复方法。

## 快速诊断工具

### 系统健康检查脚本

```bash
#!/bin/bash
# 快速系统健康检查
echo "=== Lambda Auto-Repair System Health Check ==="

# 检查核心服务状态
ENVIRONMENT=${1:-prod}
REGION=${2:-us-east-1}

echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo "=========================================="

# 1. 检查 CloudFormation 堆栈
echo "1. Checking CloudFormation Stacks..."
for stack in "main" "functions" "monitoring"; do
  stack_name="lambda-auto-repair-${stack}-${ENVIRONMENT}"
  status=$(aws cloudformation describe-stacks --stack-name $stack_name --region $REGION --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
  echo "   $stack_name: $status"
done

# 2. 检查 Lambda 函数
echo "2. Checking Lambda Functions..."
functions=("coordinator" "data-collector" "diagnosis" "executor" "verifier")
for func in "${functions[@]}"; do
  func_name="lambda-auto-repair-${func}-${ENVIRONMENT}"
  state=$(aws lambda get-function --function-name $func_name --region $REGION --query 'Configuration.State' --output text 2>/dev/null || echo "NOT_FOUND")
  echo "   $func_name: $state"
done

# 3. 检查 Step Functions
echo "3. Checking Step Functions..."
sm_name="lambda-auto-repair-workflow-${ENVIRONMENT}"
sm_status=$(aws stepfunctions describe-state-machine --state-machine-arn "arn:aws:states:${REGION}:$(aws sts get-caller-identity --query Account --output text):stateMachine:${sm_name}" --region $REGION --query 'status' --output text 2>/dev/null || echo "NOT_FOUND")
echo "   $sm_name: $sm_status"

# 4. 检查 DynamoDB 表
echo "4. Checking DynamoDB Tables..."
tables=("diagnosis" "repairs")
for table in "${tables[@]}"; do
  table_name="lambda-auto-repair-${table}-${ENVIRONMENT}"
  table_status=$(aws dynamodb describe-table --table-name $table_name --region $REGION --query 'Table.TableStatus' --output text 2>/dev/null || echo "NOT_FOUND")
  echo "   $table_name: $table_status"
done

echo "=========================================="
echo "Health check completed. Check individual components for details."
```

### 日志聚合查询

```bash
# 查看最近的系统错误
aws logs filter-log-events \
  --log-group-name "/aws/lambda/lambda-auto-repair-coordinator-prod" \
  --filter-pattern "ERROR" \
  --start-time $(date -d "1 hour ago" +%s)000 \
  --limit 20

# 查看 Step Functions 执行失败
aws stepfunctions list-executions \
  --state-machine-arn "arn:aws:states:us-east-1:ACCOUNT:stateMachine:lambda-auto-repair-workflow-prod" \
  --status-filter FAILED \
  --max-items 10
```

## 常见问题分类

## 1. 部署相关问题

### 1.1 CloudFormation 堆栈创建失败

**症状**: 
- 堆栈状态显示 `CREATE_FAILED` 或 `ROLLBACK_COMPLETE`
- 部署脚本报错退出

**诊断步骤**:

```bash
# 查看堆栈事件
aws cloudformation describe-stack-events \
  --stack-name lambda-auto-repair-main-prod \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'

# 查看详细错误信息
aws cloudformation describe-stack-events \
  --stack-name lambda-auto-repair-main-prod \
  --query 'StackEvents[0:5].{Time:Timestamp,Status:ResourceStatus,Reason:ResourceStatusReason}'
```

**常见原因和解决方案**:

1. **权限不足**
   ```bash
   # 检查当前用户权限
   aws sts get-caller-identity
   aws iam get-user
   
   # 解决方案: 确保用户具有必要的 IAM 权限
   ```

2. **资源名称冲突**
   ```bash
   # 检查是否存在同名资源
   aws s3 ls | grep lambda-auto-repair
   aws iam list-roles | grep lambda-auto-repair
   
   # 解决方案: 删除冲突资源或使用不同的环境名称
   ```

3. **服务限制**
   ```bash
   # 检查服务配额
   aws service-quotas get-service-quota \
     --service-code lambda \
     --quota-code L-B99A9384
   
   # 解决方案: 请求提高配额或清理未使用资源
   ```

4. **区域不支持服务**
   ```bash
   # 检查 Bedrock 服务可用性
   aws bedrock list-foundation-models --region us-east-1
   
   # 解决方案: 切换到支持所需服务的区域
   ```

### 1.2 Lambda 函数部署失败

**症状**:
- Lambda 函数状态显示 `Failed`
- 函数无法调用

**诊断步骤**:

```bash
# 检查函数状态
aws lambda get-function \
  --function-name lambda-auto-repair-coordinator-prod \
  --query '{State:Configuration.State,StateReason:Configuration.StateReason}'

# 查看函数配置
aws lambda get-function-configuration \
  --function-name lambda-auto-repair-coordinator-prod
```

**解决方案**:

1. **代码包过大**
   ```bash
   # 检查代码包大小
   aws lambda get-function \
     --function-name lambda-auto-repair-coordinator-prod \
     --query 'Configuration.CodeSize'
   
   # 解决方案: 优化代码包，移除不必要的依赖
   ```

2. **环境变量错误**
   ```bash
   # 检查环境变量
   aws lambda get-function-configuration \
     --function-name lambda-auto-repair-coordinator-prod \
     --query 'Environment.Variables'
   
   # 解决方案: 修正环境变量配置
   ```

3. **VPC 配置问题**
   ```bash
   # 检查 VPC 配置
   aws lambda get-function-configuration \
     --function-name lambda-auto-repair-coordinator-prod \
     --query 'VpcConfig'
   
   # 解决方案: 确保子网和安全组配置正确
   ```

## 2. 运行时问题

### 2.1 Lambda 函数执行失败

**症状**:
- 函数调用返回错误
- CloudWatch 日志显示异常

**诊断步骤**:

```bash
# 查看最近的错误日志
aws logs filter-log-events \
  --log-group-name "/aws/lambda/lambda-auto-repair-coordinator-prod" \
  --filter-pattern "ERROR" \
  --start-time $(date -d "1 hour ago" +%s)000

# 查看函数指标
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=lambda-auto-repair-coordinator-prod \
  --start-time $(date -d "1 hour ago" --iso-8601) \
  --end-time $(date --iso-8601) \
  --period 300 \
  --statistics Sum
```

**常见错误和解决方案**:

1. **超时错误**
   ```bash
   # 检查函数超时配置
   aws lambda get-function-configuration \
     --function-name lambda-auto-repair-coordinator-prod \
     --query 'Timeout'
   
   # 解决方案: 增加超时时间或优化代码性能
   aws lambda update-function-configuration \
     --function-name lambda-auto-repair-coordinator-prod \
     --timeout 300
   ```

2. **内存不足**
   ```bash
   # 查看内存使用情况
   aws logs filter-log-events \
     --log-group-name "/aws/lambda/lambda-auto-repair-coordinator-prod" \
     --filter-pattern "REPORT" \
     --limit 5
   
   # 解决方案: 增加内存配置
   aws lambda update-function-configuration \
     --function-name lambda-auto-repair-coordinator-prod \
     --memory-size 512
   ```

3. **权限错误**
   ```bash
   # 检查执行角色权限
   aws iam get-role-policy \
     --role-name lambda-auto-repair-execution-prod \
     --policy-name lambda-auto-repair-policy
   
   # 解决方案: 添加缺失的权限
   ```

4. **依赖服务不可用**
   ```bash
   # 检查 Bedrock 服务状态
   aws bedrock list-foundation-models --region us-east-1
   
   # 检查 DynamoDB 表状态
   aws dynamodb describe-table --table-name lambda-auto-repair-repairs-prod
   
   # 解决方案: 确保依赖服务正常运行
   ```

### 2.2 Step Functions 工作流失败

**症状**:
- 工作流执行状态显示 `FAILED`
- 某些步骤执行异常

**诊断步骤**:

```bash
# 查看失败的执行
aws stepfunctions list-executions \
  --state-machine-arn "arn:aws:states:us-east-1:ACCOUNT:stateMachine:lambda-auto-repair-workflow-prod" \
  --status-filter FAILED \
  --max-items 5

# 查看执行详情
aws stepfunctions describe-execution \
  --execution-arn "arn:aws:states:us-east-1:ACCOUNT:execution:lambda-auto-repair-workflow-prod:execution-id"

# 查看执行历史
aws stepfunctions get-execution-history \
  --execution-arn "arn:aws:states:us-east-1:ACCOUNT:execution:lambda-auto-repair-workflow-prod:execution-id"
```

**解决方案**:

1. **任务状态失败**
   ```bash
   # 检查失败的任务状态
   aws stepfunctions get-execution-history \
     --execution-arn "arn:aws:states:us-east-1:ACCOUNT:execution:lambda-auto-repair-workflow-prod:execution-id" \
     --query 'events[?type==`TaskFailed`]'
   
   # 解决方案: 修复对应的 Lambda 函数或服务
   ```

2. **状态机定义错误**
   ```bash
   # 验证状态机定义
   aws stepfunctions describe-state-machine \
     --state-machine-arn "arn:aws:states:us-east-1:ACCOUNT:stateMachine:lambda-auto-repair-workflow-prod" \
     --query 'definition' | jq .
   
   # 解决方案: 更新状态机定义
   ```

3. **输入数据格式错误**
   ```bash
   # 检查输入数据
   aws stepfunctions describe-execution \
     --execution-arn "arn:aws:states:us-east-1:ACCOUNT:execution:lambda-auto-repair-workflow-prod:execution-id" \
     --query 'input'
   
   # 解决方案: 修正输入数据格式
   ```

### 2.3 EventBridge 事件路由问题

**症状**:
- 告警触发但没有启动修复流程
- 事件没有正确路由到目标

**诊断步骤**:

```bash
# 检查事件规则状态
aws events list-rules \
  --event-bus-name lambda-auto-repair-prod \
  --query 'Rules[].{Name:Name,State:State}'

# 查看规则详情
aws events describe-rule \
  --name lambda-auto-repair-alarm-rule \
  --event-bus-name lambda-auto-repair-prod

# 检查规则目标
aws events list-targets-by-rule \
  --rule lambda-auto-repair-alarm-rule \
  --event-bus-name lambda-auto-repair-prod
```

**解决方案**:

1. **规则被禁用**
   ```bash
   # 启用规则
   aws events enable-rule \
     --name lambda-auto-repair-alarm-rule \
     --event-bus-name lambda-auto-repair-prod
   ```

2. **事件模式不匹配**
   ```bash
   # 检查事件模式
   aws events describe-rule \
     --name lambda-auto-repair-alarm-rule \
     --event-bus-name lambda-auto-repair-prod \
     --query 'EventPattern'
   
   # 解决方案: 更新事件模式以匹配实际事件
   ```

3. **目标配置错误**
   ```bash
   # 检查目标权限
   aws iam get-role-policy \
     --role-name lambda-auto-repair-eventbridge-role \
     --policy-name eventbridge-policy
   
   # 解决方案: 修正目标配置和权限
   ```

## 3. 监控和告警问题

### 3.1 CloudWatch 告警不触发

**症状**:
- Lambda 函数出现性能问题但没有告警
- 告警状态一直显示 `INSUFFICIENT_DATA`

**诊断步骤**:

```bash
# 检查告警配置
aws cloudwatch describe-alarms \
  --alarm-names "lambda-duration-alarm-my-function" \
  --query 'MetricAlarms[0].{State:StateValue,Reason:StateReason,Config:AlarmConfiguration}'

# 检查指标数据
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=my-target-function \
  --start-time $(date -d "1 hour ago" --iso-8601) \
  --end-time $(date --iso-8601) \
  --period 300 \
  --statistics Average
```

**解决方案**:

1. **指标数据不足**
   ```bash
   # 检查函数是否有执行
   aws cloudwatch get-metric-statistics \
     --namespace AWS/Lambda \
     --metric-name Invocations \
     --dimensions Name=FunctionName,Value=my-target-function \
     --start-time $(date -d "1 hour ago" --iso-8601) \
     --end-time $(date --iso-8601) \
     --period 300 \
     --statistics Sum
   
   # 解决方案: 确保函数有足够的执行次数产生指标数据
   ```

2. **告警阈值设置不当**
   ```bash
   # 分析历史数据确定合适的阈值
   aws cloudwatch get-metric-statistics \
     --namespace AWS/Lambda \
     --metric-name Duration \
     --dimensions Name=FunctionName,Value=my-target-function \
     --start-time $(date -d "7 days ago" --iso-8601) \
     --end-time $(date --iso-8601) \
     --period 3600 \
     --statistics Average,Maximum
   
   # 解决方案: 调整告警阈值
   ```

3. **告警操作配置错误**
   ```bash
   # 检查 SNS 主题权限
   aws sns get-topic-attributes \
     --topic-arn "arn:aws:sns:us-east-1:ACCOUNT:lambda-auto-repair-notifications-prod"
   
   # 解决方案: 修正 SNS 主题权限和订阅
   ```

### 3.2 监控数据缺失

**症状**:
- CloudWatch 仪表板显示数据缺失
- 指标查询返回空结果

**诊断步骤**:

```bash
# 检查 Lambda 函数日志
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/lambda/lambda-auto-repair"

# 检查日志流
aws logs describe-log-streams \
  --log-group-name "/aws/lambda/lambda-auto-repair-coordinator-prod" \
  --order-by LastEventTime \
  --descending \
  --max-items 5
```

**解决方案**:

1. **日志组被删除**
   ```bash
   # 重新创建日志组
   aws logs create-log-group \
     --log-group-name "/aws/lambda/lambda-auto-repair-coordinator-prod"
   
   # 设置保留期
   aws logs put-retention-policy \
     --log-group-name "/aws/lambda/lambda-auto-repair-coordinator-prod" \
     --retention-in-days 30
   ```

2. **权限问题**
   ```bash
   # 检查 Lambda 执行角色权限
   aws iam get-role-policy \
     --role-name lambda-auto-repair-execution-prod \
     --policy-name lambda-auto-repair-policy
   
   # 解决方案: 添加 CloudWatch Logs 权限
   ```

## 4. 数据存储问题

### 4.1 DynamoDB 访问错误

**症状**:
- 读写操作失败
- 表状态异常

**诊断步骤**:

```bash
# 检查表状态
aws dynamodb describe-table \
  --table-name lambda-auto-repair-repairs-prod \
  --query 'Table.{Status:TableStatus,ItemCount:ItemCount}'

# 检查表指标
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ThrottledRequests \
  --dimensions Name=TableName,Value=lambda-auto-repair-repairs-prod \
  --start-time $(date -d "1 hour ago" --iso-8601) \
  --end-time $(date --iso-8601) \
  --period 300 \
  --statistics Sum
```

**解决方案**:

1. **容量不足**
   ```bash
   # 检查容量使用情况
   aws dynamodb describe-table \
     --table-name lambda-auto-repair-repairs-prod \
     --query 'Table.{ReadCapacity:ProvisionedThroughput.ReadCapacityUnits,WriteCapacity:ProvisionedThroughput.WriteCapacityUnits}'
   
   # 解决方案: 增加预置容量或切换到按需计费
   aws dynamodb modify-table \
     --table-name lambda-auto-repair-repairs-prod \
     --billing-mode PAY_PER_REQUEST
   ```

2. **热分区问题**
   ```bash
   # 分析访问模式
   aws dynamodb scan \
     --table-name lambda-auto-repair-repairs-prod \
     --select COUNT
   
   # 解决方案: 优化分区键设计或使用 GSI
   ```

3. **权限问题**
   ```bash
   # 检查 IAM 权限
   aws iam simulate-principal-policy \
     --policy-source-arn "arn:aws:iam::ACCOUNT:role/lambda-auto-repair-execution-prod" \
     --action-names dynamodb:PutItem \
     --resource-arns "arn:aws:dynamodb:us-east-1:ACCOUNT:table/lambda-auto-repair-repairs-prod"
   
   # 解决方案: 添加必要的 DynamoDB 权限
   ```

### 4.2 数据一致性问题

**症状**:
- 数据读取不一致
- 修复记录丢失

**诊断步骤**:

```bash
# 检查最近的写入操作
aws dynamodb scan \
  --table-name lambda-auto-repair-repairs-prod \
  --filter-expression "executedAt > :yesterday" \
  --expression-attribute-values '{":yesterday":{"S":"2024-01-01T00:00:00Z"}}' \
  --consistent-read

# 检查 GSI 状态
aws dynamodb describe-table \
  --table-name lambda-auto-repair-repairs-prod \
  --query 'Table.GlobalSecondaryIndexes[].{IndexName:IndexName,Status:IndexStatus}'
```

**解决方案**:

1. **最终一致性问题**
   ```bash
   # 使用强一致性读取
   aws dynamodb get-item \
     --table-name lambda-auto-repair-repairs-prod \
     --key '{"repairId":{"S":"repair-123"}}' \
     --consistent-read
   
   # 解决方案: 在关键操作中使用强一致性读取
   ```

2. **并发写入冲突**
   ```bash
   # 使用条件写入
   aws dynamodb put-item \
     --table-name lambda-auto-repair-repairs-prod \
     --item '{"repairId":{"S":"repair-123"},"status":{"S":"completed"}}' \
     --condition-expression "attribute_not_exists(repairId)"
   
   # 解决方案: 实现乐观锁机制
   ```

## 5. 集成服务问题

### 5.1 Bedrock 服务访问问题

**症状**:
- 诊断请求失败
- 模型调用超时

**诊断步骤**:

```bash
# 检查 Bedrock 服务可用性
aws bedrock list-foundation-models --region us-east-1

# 检查知识库状态
aws bedrock-agent get-knowledge-base \
  --knowledge-base-id "kb-1234567890abcdef"

# 测试模型调用
aws bedrock-runtime invoke-model \
  --model-id "anthropic.claude-3-sonnet-20240229-v1:0" \
  --body '{"prompt":"Test prompt","max_tokens":100}' \
  --content-type "application/json" \
  --accept "application/json" \
  /tmp/bedrock-response.json
```

**解决方案**:

1. **区域不支持**
   ```bash
   # 检查支持的区域
   aws bedrock list-foundation-models --region us-west-2
   
   # 解决方案: 切换到支持 Bedrock 的区域
   ```

2. **模型访问权限**
   ```bash
   # 检查模型访问权限
   aws bedrock get-model-invocation-logging-configuration
   
   # 解决方案: 在 Bedrock 控制台中请求模型访问权限
   ```

3. **知识库同步问题**
   ```bash
   # 检查数据源同步状态
   aws bedrock-agent list-ingestion-jobs \
     --knowledge-base-id "kb-1234567890abcdef" \
     --data-source-id "ds-1234567890abcdef"
   
   # 解决方案: 重新同步知识库
   aws bedrock-agent start-ingestion-job \
     --knowledge-base-id "kb-1234567890abcdef" \
     --data-source-id "ds-1234567890abcdef"
   ```

### 5.2 SNS 通知问题

**症状**:
- 通知邮件未收到
- Slack 集成失败

**诊断步骤**:

```bash
# 检查 SNS 主题状态
aws sns get-topic-attributes \
  --topic-arn "arn:aws:sns:us-east-1:ACCOUNT:lambda-auto-repair-notifications-prod"

# 检查订阅状态
aws sns list-subscriptions-by-topic \
  --topic-arn "arn:aws:sns:us-east-1:ACCOUNT:lambda-auto-repair-notifications-prod"

# 测试消息发送
aws sns publish \
  --topic-arn "arn:aws:sns:us-east-1:ACCOUNT:lambda-auto-repair-notifications-prod" \
  --message "Test notification from Lambda Auto-Repair System"
```

**解决方案**:

1. **邮件订阅未确认**
   ```bash
   # 检查订阅确认状态
   aws sns list-subscriptions-by-topic \
     --topic-arn "arn:aws:sns:us-east-1:ACCOUNT:lambda-auto-repair-notifications-prod" \
     --query 'Subscriptions[].{Protocol:Protocol,Endpoint:Endpoint,ConfirmationWasAuthenticated:ConfirmationWasAuthenticated}'
   
   # 解决方案: 重新发送确认邮件
   aws sns confirm-subscription \
     --topic-arn "arn:aws:sns:us-east-1:ACCOUNT:lambda-auto-repair-notifications-prod" \
     --token "confirmation-token"
   ```

2. **消息格式问题**
   ```bash
   # 检查消息属性
   aws sns get-topic-attributes \
     --topic-arn "arn:aws:sns:us-east-1:ACCOUNT:lambda-auto-repair-notifications-prod" \
     --query 'Attributes.DisplayName'
   
   # 解决方案: 调整消息格式和属性
   ```

3. **Lambda 集成失败**
   ```bash
   # 检查 Lambda 函数权限
   aws lambda get-policy \
     --function-name slack-notifier
   
   # 解决方案: 添加 SNS 调用权限
   aws lambda add-permission \
     --function-name slack-notifier \
     --statement-id sns-invoke \
     --action lambda:InvokeFunction \
     --principal sns.amazonaws.com \
     --source-arn "arn:aws:sns:us-east-1:ACCOUNT:lambda-auto-repair-notifications-prod"
   ```

## 6. 性能问题

### 6.1 系统响应缓慢

**症状**:
- 修复流程执行时间过长
- Lambda 函数冷启动频繁

**诊断步骤**:

```bash
# 分析 Lambda 函数性能
aws logs filter-log-events \
  --log-group-name "/aws/lambda/lambda-auto-repair-coordinator-prod" \
  --filter-pattern "REPORT" \
  --start-time $(date -d "1 hour ago" +%s)000 \
  --limit 20

# 分析 Step Functions 执行时间
aws stepfunctions list-executions \
  --state-machine-arn "arn:aws:states:us-east-1:ACCOUNT:stateMachine:lambda-auto-repair-workflow-prod" \
  --status-filter SUCCEEDED \
  --max-items 10
```

**解决方案**:

1. **Lambda 冷启动优化**
   ```bash
   # 增加预留并发
   aws lambda put-provisioned-concurrency-config \
     --function-name lambda-auto-repair-coordinator-prod \
     --provisioned-concurrency-config ProvisionedConcurrencyUnits=2
   
   # 优化内存配置
   aws lambda update-function-configuration \
     --function-name lambda-auto-repair-coordinator-prod \
     --memory-size 1024
   ```

2. **DynamoDB 性能优化**
   ```bash
   # 启用 DAX 缓存（如果适用）
   aws dax create-cluster \
     --cluster-name lambda-auto-repair-cache \
     --node-type dax.t3.small \
     --replication-factor 1 \
     --iam-role-arn "arn:aws:iam::ACCOUNT:role/DAXServiceRole"
   ```

3. **并行处理优化**
   ```bash
   # 调整 Step Functions 并行度
   # 在状态机定义中使用 Parallel 状态
   ```

### 6.2 资源使用率过高

**症状**:
- Lambda 函数内存使用率接近限制
- DynamoDB 读写容量经常被限流

**诊断步骤**:

```bash
# 分析内存使用模式
aws logs filter-log-events \
  --log-group-name "/aws/lambda/lambda-auto-repair-coordinator-prod" \
  --filter-pattern "Max Memory Used" \
  --start-time $(date -d "24 hours ago" +%s)000

# 检查 DynamoDB 限流情况
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ThrottledRequests \
  --dimensions Name=TableName,Value=lambda-auto-repair-repairs-prod \
  --start-time $(date -d "24 hours ago" --iso-8601) \
  --end-time $(date --iso-8601) \
  --period 3600 \
  --statistics Sum
```

**解决方案**:

1. **内存优化**
   ```bash
   # 分析内存使用趋势
   # 根据实际使用情况调整内存配置
   aws lambda update-function-configuration \
     --function-name lambda-auto-repair-coordinator-prod \
     --memory-size 512
   ```

2. **数据库容量优化**
   ```bash
   # 切换到按需计费模式
   aws dynamodb modify-table \
     --table-name lambda-auto-repair-repairs-prod \
     --billing-mode PAY_PER_REQUEST
   
   # 或者增加预置容量
   aws dynamodb modify-table \
     --table-name lambda-auto-repair-repairs-prod \
     --provisioned-throughput ReadCapacityUnits=10,WriteCapacityUnits=10
   ```

## 7. 安全问题

### 7.1 权限访问错误

**症状**:
- API 调用返回权限拒绝错误
- 跨服务访问失败

**诊断步骤**:

```bash
# 检查 IAM 角色权限
aws iam get-role-policy \
  --role-name lambda-auto-repair-execution-prod \
  --policy-name lambda-auto-repair-policy

# 模拟权限检查
aws iam simulate-principal-policy \
  --policy-source-arn "arn:aws:iam::ACCOUNT:role/lambda-auto-repair-execution-prod" \
  --action-names lambda:UpdateFunctionConfiguration \
  --resource-arns "arn:aws:lambda:us-east-1:ACCOUNT:function:target-function"

# 检查信任关系
aws iam get-role \
  --role-name lambda-auto-repair-execution-prod \
  --query 'Role.AssumeRolePolicyDocument'
```

**解决方案**:

1. **添加缺失权限**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "lambda:UpdateFunctionConfiguration",
           "lambda:GetFunction"
         ],
         "Resource": "arn:aws:lambda:*:*:function:*"
       }
     ]
   }
   ```

2. **修复信任关系**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Service": "lambda.amazonaws.com"
         },
         "Action": "sts:AssumeRole"
       }
     ]
   }
   ```

### 7.2 加密相关问题

**症状**:
- KMS 密钥访问被拒绝
- 数据解密失败

**诊断步骤**:

```bash
# 检查 KMS 密钥状态
aws kms describe-key \
  --key-id "arn:aws:kms:us-east-1:ACCOUNT:key/key-id"

# 检查密钥权限
aws kms get-key-policy \
  --key-id "arn:aws:kms:us-east-1:ACCOUNT:key/key-id" \
  --policy-name default

# 测试加密解密
aws kms encrypt \
  --key-id "arn:aws:kms:us-east-1:ACCOUNT:key/key-id" \
  --plaintext "test data"
```

**解决方案**:

1. **更新密钥策略**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "AWS": "arn:aws:iam::ACCOUNT:role/lambda-auto-repair-execution-prod"
         },
         "Action": [
           "kms:Encrypt",
           "kms:Decrypt",
           "kms:GenerateDataKey"
         ],
         "Resource": "*"
       }
     ]
   }
   ```

2. **检查密钥轮换**
   ```bash
   # 启用自动轮换
   aws kms enable-key-rotation \
     --key-id "arn:aws:kms:us-east-1:ACCOUNT:key/key-id"
   ```

## 紧急响应流程

### 系统完全故障

1. **立即响应**
   ```bash
   # 检查系统整体状态
   ./health-check.sh prod us-east-1
   
   # 查看最近的错误
   aws logs filter-log-events \
     --log-group-name "/aws/lambda/lambda-auto-repair-coordinator-prod" \
     --filter-pattern "ERROR" \
     --start-time $(date -d "30 minutes ago" +%s)000
   ```

2. **临时禁用自动修复**
   ```bash
   # 禁用所有 EventBridge 规则
   aws events list-rules --event-bus-name lambda-auto-repair-prod \
     --query 'Rules[].Name' --output text | \
     xargs -I {} aws events disable-rule --name {} --event-bus-name lambda-auto-repair-prod
   ```

3. **通知相关团队**
   ```bash
   # 发送紧急通知
   aws sns publish \
     --topic-arn "arn:aws:sns:us-east-1:ACCOUNT:emergency-notifications" \
     --message "Lambda Auto-Repair System is experiencing critical issues. Auto-repair has been disabled."
   ```

4. **收集诊断信息**
   ```bash
   # 生成完整的系统状态报告
   ./generate-diagnostic-report.sh prod > system-diagnostic-$(date +%Y%m%d-%H%M%S).txt
   ```

### 联系信息

- **紧急联系**: on-call-engineer@example.com
- **技术支持**: platform-team@example.com
- **AWS 支持**: 通过 AWS Support Center 创建案例

---

**注意**: 本故障排除指南应定期更新，确保包含最新的问题和解决方案。建议每月审查一次常见问题列表。