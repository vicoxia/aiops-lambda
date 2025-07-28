#!/bin/bash

# 触发测试并监控自动修复过程的脚本

set -e

# 配置参数
FUNCTION_NAME="lambda-auto-repair-test-function"
ENVIRONMENT="dev"
REGION="us-east-1"

echo "=== Lambda自动修复系统测试 ==="
echo "函数名称: $FUNCTION_NAME"
echo "环境: $ENVIRONMENT"
echo "区域: $REGION"
echo "================================"

# 函数：获取函数当前配置
get_function_config() {
    aws lambda get-function-configuration \
        --function-name $FUNCTION_NAME \
        --region $REGION \
        --query '{MemorySize:MemorySize,Timeout:Timeout,LastModified:LastModified}' \
        --output table
}

# 函数：调用测试函数
invoke_test_function() {
    local test_payload='{"test": "memory-exhaustion", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
    
    echo "调用测试函数..."
    aws lambda invoke \
        --function-name $FUNCTION_NAME \
        --payload "$test_payload" \
        --region $REGION \
        response.json
    
    echo "函数响应:"
    cat response.json | jq .
    rm -f response.json
}

# 函数：监控告警状态
monitor_alarms() {
    echo "监控告警状态..."
    aws cloudwatch describe-alarms \
        --alarm-name-prefix "${FUNCTION_NAME}-" \
        --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Reason:StateReason,Timestamp:StateUpdatedTimestamp}' \
        --output table \
        --region $REGION
}

# 函数：检查Step Functions执行
check_step_functions() {
    local state_machine_name="lambda-auto-repair-workflow-${ENVIRONMENT}"
    echo "检查Step Functions执行..."
    
    aws stepfunctions list-executions \
        --state-machine-arn "arn:aws:states:${REGION}:$(aws sts get-caller-identity --query Account --output text):stateMachine:${state_machine_name}" \
        --max-items 5 \
        --query 'executions[].{Name:name,Status:status,StartDate:startDate}' \
        --output table
}

# 函数：查看最近的日志
view_recent_logs() {
    local log_group="/aws/lambda/$FUNCTION_NAME"
    echo "查看最近的函数日志..."
    
    # 获取最新的日志流
    local latest_stream=$(aws logs describe-log-streams \
        --log-group-name $log_group \
        --order-by LastEventTime \
        --descending \
        --max-items 1 \
        --query 'logStreams[0].logStreamName' \
        --output text \
        --region $REGION 2>/dev/null || echo "")
    
    if [ -n "$latest_stream" ] && [ "$latest_stream" != "None" ]; then
        aws logs get-log-events \
            --log-group-name $log_group \
            --log-stream-name "$latest_stream" \
            --limit 10 \
            --query 'events[].message' \
            --output text \
            --region $REGION
    else
        echo "没有找到日志流"
    fi
}

echo "步骤1: 查看函数初始配置"
get_function_config

echo ""
echo "步骤2: 触发测试函数（第1次 - 应该会因内存不足而失败或超时）"
invoke_test_function

echo ""
echo "步骤3: 等待5秒让指标生成..."
sleep 5

echo ""
echo "步骤4: 再次调用函数以确保触发告警"
invoke_test_function

echo ""
echo "步骤5: 等待10秒让告警触发..."
sleep 10

echo ""
echo "步骤6: 检查告警状态"
monitor_alarms

echo ""
echo "步骤7: 查看函数日志"
view_recent_logs

echo ""
echo "步骤8: 检查Step Functions执行（如果有的话）"
check_step_functions

echo ""
echo "步骤9: 等待30秒让自动修复系统工作..."
echo "在此期间，系统应该："
echo "1. 检测到告警"
echo "2. 收集指标和日志数据"
echo "3. 使用Bedrock进行诊断"
echo "4. 执行内存增加修复"
echo "5. 验证修复效果"
echo "6. 发送通知"

for i in {30..1}; do
    echo -ne "\r等待中... $i 秒"
    sleep 1
done
echo ""

echo ""
echo "步骤10: 检查函数配置是否已更新"
echo "如果自动修复成功，内存大小应该已经增加："
get_function_config

echo ""
echo "步骤11: 使用更新后的配置再次测试函数"
invoke_test_function

echo ""
echo "步骤12: 最终告警状态检查"
monitor_alarms

echo ""
echo "=== 测试完成 ==="
echo "检查以下内容来验证自动修复是否成功："
echo "1. 函数内存大小是否已增加（从128MB增加到更高值）"
echo "2. 最后一次函数调用是否成功"
echo "3. 告警状态是否恢复正常"
echo "4. 是否收到SNS通知邮件"
echo ""
echo "如需查看详细日志，请检查："
echo "- CloudWatch日志组: /aws/lambda/$FUNCTION_NAME"
echo "- 自动修复系统日志: /aws/lambda/lambda-auto-repair-coordinator-$ENVIRONMENT"
echo "- Step Functions执行历史"