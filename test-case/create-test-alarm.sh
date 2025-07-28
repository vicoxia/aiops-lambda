#!/bin/bash

# 为测试函数创建CloudWatch告警的脚本

set -e

# 配置参数
FUNCTION_NAME="lambda-auto-repair-test-function"
ENVIRONMENT="dev"
REGION="us-east-1"
SNS_TOPIC_ARN="arn:aws:sns:${REGION}:$(aws sts get-caller-identity --query Account --output text):lambda-auto-repair-notifications-${ENVIRONMENT}"

echo "=== 创建测试告警 ==="
echo "函数名称: $FUNCTION_NAME"
echo "SNS主题: $SNS_TOPIC_ARN"
echo "========================"

# 创建Duration告警（持续时间超过阈值）
echo "创建Duration告警..."
aws cloudwatch put-metric-alarm \
    --alarm-name "${FUNCTION_NAME}-duration-alarm" \
    --alarm-description "Test alarm for Lambda function duration" \
    --metric-name Duration \
    --namespace AWS/Lambda \
    --statistic Average \
    --period 60 \
    --threshold 25000 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=FunctionName,Value=$FUNCTION_NAME \
    --evaluation-periods 1 \
    --datapoints-to-alarm 1 \
    --alarm-actions $SNS_TOPIC_ARN \
    --region $REGION

# 创建Errors告警（错误数量超过阈值）
echo "创建Errors告警..."
aws cloudwatch put-metric-alarm \
    --alarm-name "${FUNCTION_NAME}-errors-alarm" \
    --alarm-description "Test alarm for Lambda function errors" \
    --metric-name Errors \
    --namespace AWS/Lambda \
    --statistic Sum \
    --period 60 \
    --threshold 0 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=FunctionName,Value=$FUNCTION_NAME \
    --evaluation-periods 1 \
    --datapoints-to-alarm 1 \
    --alarm-actions $SNS_TOPIC_ARN \
    --region $REGION

# 创建Throttles告警（限流次数超过阈值）
echo "创建Throttles告警..."
aws cloudwatch put-metric-alarm \
    --alarm-name "${FUNCTION_NAME}-throttles-alarm" \
    --alarm-description "Test alarm for Lambda function throttles" \
    --metric-name Throttles \
    --namespace AWS/Lambda \
    --statistic Sum \
    --period 60 \
    --threshold 0 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=FunctionName,Value=$FUNCTION_NAME \
    --evaluation-periods 1 \
    --datapoints-to-alarm 1 \
    --alarm-actions $SNS_TOPIC_ARN \
    --region $REGION

echo "告警创建完成！"

# 验证告警状态
echo ""
echo "=== 验证告警状态 ==="
aws cloudwatch describe-alarms \
    --alarm-names "${FUNCTION_NAME}-duration-alarm" "${FUNCTION_NAME}-errors-alarm" "${FUNCTION_NAME}-throttles-alarm" \
    --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Reason:StateReason}' \
    --output table \
    --region $REGION

echo ""
echo "=== 下一步 ==="
echo "运行 ./test-case/trigger-test.sh 开始测试自动修复流程"