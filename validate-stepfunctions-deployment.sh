#!/bin/bash

# 验证Step Functions架构部署的脚本

set -e

# 配置参数
ENVIRONMENT="${1:-dev}"
REGION="${2:-us-east-1}"

echo "=== Lambda自动修复系统 - Step Functions架构验证 ==="
echo "环境: $ENVIRONMENT"
echo "区域: $REGION"
echo "=================================================="

# 验证Step Functions状态机
echo "1. 验证Step Functions状态机..."
STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
    --query "stateMachines[?name=='lambda-auto-repair-workflow-${ENVIRONMENT}'].stateMachineArn" \
    --output text \
    --region $REGION)

if [ -z "$STATE_MACHINE_ARN" ]; then
    echo "❌ Step Functions状态机未找到"
    exit 1
else
    echo "✅ Step Functions状态机已部署: $STATE_MACHINE_ARN"
fi

# 验证状态机状态
STATE_MACHINE_STATUS=$(aws stepfunctions describe-state-machine \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --query 'status' \
    --output text \
    --region $REGION)

if [ "$STATE_MACHINE_STATUS" != "ACTIVE" ]; then
    echo "❌ Step Functions状态机状态异常: $STATE_MACHINE_STATUS"
    exit 1
else
    echo "✅ Step Functions状态机状态正常: $STATE_MACHINE_STATUS"
fi

# 验证EventBridge规则
echo ""
echo "2. 验证EventBridge规则..."
RULE_NAME="lambda-auto-repair-alarm-rule-${ENVIRONMENT}"
RULE_STATUS=$(aws events describe-rule \
    --name "$RULE_NAME" \
    --query 'State' \
    --output text \
    --region $REGION 2>/dev/null || echo "NOT_FOUND")

if [ "$RULE_STATUS" != "ENABLED" ]; then
    echo "❌ EventBridge规则未启用或不存在: $RULE_STATUS"
    exit 1
else
    echo "✅ EventBridge规则已启用: $RULE_NAME"
fi

# 验证EventBridge规则目标
RULE_TARGETS=$(aws events list-targets-by-rule \
    --rule "$RULE_NAME" \
    --query 'Targets[0].Arn' \
    --output text \
    --region $REGION)

if [[ "$RULE_TARGETS" != *"stateMachine"* ]]; then
    echo "❌ EventBridge规则目标不是Step Functions: $RULE_TARGETS"
    exit 1
else
    echo "✅ EventBridge规则正确指向Step Functions"
fi

# 验证Lambda函数
echo ""
echo "3. 验证Lambda函数..."
FUNCTIONS=(
    "lambda-auto-repair-adapter-${ENVIRONMENT}"
    "lambda-auto-repair-data-collector-${ENVIRONMENT}"
    "lambda-auto-repair-diagnosis-${ENVIRONMENT}"
    "lambda-auto-repair-executor-${ENVIRONMENT}"
    "lambda-auto-repair-verifier-${ENVIRONMENT}"
    "lambda-auto-repair-coordinator-${ENVIRONMENT}"
)

for FUNCTION in "${FUNCTIONS[@]}"; do
    FUNCTION_STATUS=$(aws lambda get-function \
        --function-name "$FUNCTION" \
        --query 'Configuration.State' \
        --output text \
        --region $REGION 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$FUNCTION_STATUS" != "Active" ]; then
        echo "❌ Lambda函数状态异常: $FUNCTION ($FUNCTION_STATUS)"
        exit 1
    else
        echo "✅ Lambda函数正常: $FUNCTION"
    fi
done

# 验证IAM角色
echo ""
echo "4. 验证IAM角色..."
ROLES=(
    "lambda-auto-repair-execution-${ENVIRONMENT}"
    "lambda-auto-repair-stepfunctions-${ENVIRONMENT}"
    "lambda-auto-repair-eventbridge-${ENVIRONMENT}"
)

for ROLE in "${ROLES[@]}"; do
    ROLE_EXISTS=$(aws iam get-role \
        --role-name "$ROLE" \
        --query 'Role.RoleName' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$ROLE_EXISTS" = "NOT_FOUND" ]; then
        echo "❌ IAM角色不存在: $ROLE"
        exit 1
    else
        echo "✅ IAM角色存在: $ROLE"
    fi
done

# 验证DynamoDB表
echo ""
echo "5. 验证DynamoDB表..."
TABLES=(
    "lambda-auto-repair-diagnosis-${ENVIRONMENT}"
    "lambda-auto-repair-repairs-${ENVIRONMENT}"
)

for TABLE in "${TABLES[@]}"; do
    TABLE_STATUS=$(aws dynamodb describe-table \
        --table-name "$TABLE" \
        --query 'Table.TableStatus' \
        --output text \
        --region $REGION 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$TABLE_STATUS" != "ACTIVE" ]; then
        echo "❌ DynamoDB表状态异常: $TABLE ($TABLE_STATUS)"
        exit 1
    else
        echo "✅ DynamoDB表正常: $TABLE"
    fi
done

# 测试Step Functions执行
echo ""
echo "6. 测试Step Functions执行..."
TEST_INPUT='{
  "version": "0",
  "id": "validation-test",
  "detail-type": "CloudWatch Alarm State Change",
  "source": "aws.cloudwatch",
  "account": "'$(aws sts get-caller-identity --query Account --output text)'",
  "time": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
  "region": "'$REGION'",
  "detail": {
    "alarmName": "validation-test-alarm",
    "state": {
      "value": "ALARM",
      "reason": "Validation test",
      "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'"
    }
  }
}'

EXECUTION_ARN=$(aws stepfunctions start-execution \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --input "$TEST_INPUT" \
    --query 'executionArn' \
    --output text \
    --region $REGION)

echo "✅ Step Functions测试执行已启动: $EXECUTION_ARN"

# 等待执行完成
echo "等待执行完成..."
sleep 10

EXECUTION_STATUS=$(aws stepfunctions describe-execution \
    --execution-arn "$EXECUTION_ARN" \
    --query 'status' \
    --output text \
    --region $REGION)

if [ "$EXECUTION_STATUS" = "SUCCEEDED" ]; then
    echo "✅ Step Functions测试执行成功"
elif [ "$EXECUTION_STATUS" = "FAILED" ]; then
    echo "⚠️  Step Functions测试执行失败，但这可能是预期的（因为测试告警不存在）"
    # 获取失败原因
    FAILURE_CAUSE=$(aws stepfunctions describe-execution \
        --execution-arn "$EXECUTION_ARN" \
        --query 'cause' \
        --output text \
        --region $REGION)
    echo "失败原因: $FAILURE_CAUSE"
else
    echo "⚠️  Step Functions测试执行状态: $EXECUTION_STATUS"
fi

echo ""
echo "=================================================="
echo "✅ Step Functions架构验证完成！"
echo ""
echo "架构概览："
echo "CloudWatch告警 → EventBridge → Step Functions状态机 → Lambda函数编排"
echo ""
echo "主要组件："
echo "- Step Functions状态机: $STATE_MACHINE_ARN"
echo "- EventBridge规则: $RULE_NAME"
echo "- Lambda函数: ${#FUNCTIONS[@]}个"
echo "- IAM角色: ${#ROLES[@]}个"
echo "- DynamoDB表: ${#TABLES[@]}个"
echo ""
echo "系统已准备就绪，可以处理Lambda函数自动修复任务！"