#!/bin/bash

# 监控自动修复系统运行状态的脚本

set -e

# 配置参数
ENVIRONMENT="dev"
REGION="us-east-1"
FUNCTION_NAME="lambda-auto-repair-test-function"

echo "=== Lambda自动修复系统监控 ==="
echo "环境: $ENVIRONMENT"
echo "区域: $REGION"
echo "================================"

# 函数：检查系统组件状态
check_system_components() {
    echo "=== 系统组件状态 ==="
    
    # 检查Lambda函数
    echo "Lambda函数状态:"
    aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `lambda-auto-repair`)].{Name:FunctionName,State:State,Runtime:Runtime}' \
        --output table \
        --region $REGION
    
    echo ""
    # 检查Step Functions
    echo "Step Functions状态:"
    aws stepfunctions list-state-machines \
        --query 'stateMachines[?contains(name, `lambda-auto-repair`)].{Name:name,Status:status}' \
        --output table
    
    echo ""
    # 检查DynamoDB表
    echo "DynamoDB表状态:"
    aws dynamodb list-tables \
        --query 'TableNames[?contains(@, `lambda-auto-repair`)]' \
        --output table \
        --region $REGION
}

# 函数：查看最近的诊断记录
view_diagnosis_records() {
    echo "=== 最近的诊断记录 ==="
    local table_name="lambda-auto-repair-diagnosis-${ENVIRONMENT}"
    
    # 扫描最近的记录
    aws dynamodb scan \
        --table-name $table_name \
        --limit 5 \
        --query 'Items[].{DiagnosisId:diagnosisId.S,FunctionName:functionName.S,Timestamp:timestamp.S,IsMemoryIssue:isMemoryIssue.BOOL}' \
        --output table \
        --region $REGION 2>/dev/null || echo "没有找到诊断记录或表不存在"
}

# 函数：查看最近的修复记录
view_repair_records() {
    echo "=== 最近的修复记录 ==="
    local table_name="lambda-auto-repair-repairs-${ENVIRONMENT}"
    
    # 扫描最近的记录
    aws dynamodb scan \
        --table-name $table_name \
        --limit 5 \
        --query 'Items[].{RepairId:repairId.S,FunctionName:functionName.S,OriginalMemory:originalMemory.N,NewMemory:newMemory.N,Status:status.S}' \
        --output table \
        --region $REGION 2>/dev/null || echo "没有找到修复记录或表不存在"
}

# 函数：查看CloudWatch指标
view_cloudwatch_metrics() {
    echo "=== CloudWatch指标 ==="
    
    # 获取测试函数的最近指标
    local end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local start_time=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
    
    echo "测试函数指标 (最近1小时):"
    aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Duration \
        --dimensions Name=FunctionName,Value=$FUNCTION_NAME \
        --start-time $start_time \
        --end-time $end_time \
        --period 300 \
        --statistics Average,Maximum \
        --query 'Datapoints[].{Timestamp:Timestamp,Average:Average,Maximum:Maximum}' \
        --output table \
        --region $REGION 2>/dev/null || echo "没有找到指标数据"
}

# 函数：查看Step Functions执行历史
view_step_functions_history() {
    echo "=== Step Functions执行历史 ==="
    local state_machine_name="lambda-auto-repair-workflow-${ENVIRONMENT}"
    local state_machine_arn="arn:aws:states:${REGION}:$(aws sts get-caller-identity --query Account --output text):stateMachine:${state_machine_name}"
    
    aws stepfunctions list-executions \
        --state-machine-arn $state_machine_arn \
        --max-items 10 \
        --query 'executions[].{Name:name,Status:status,StartDate:startDate,StopDate:stopDate}' \
        --output table 2>/dev/null || echo "没有找到Step Functions执行记录"
}

# 函数：查看系统日志
view_system_logs() {
    echo "=== 系统日志 ==="
    local coordinator_log_group="/aws/lambda/lambda-auto-repair-coordinator-${ENVIRONMENT}"
    
    echo "协调器函数最近日志:"
    aws logs filter-log-events \
        --log-group-name $coordinator_log_group \
        --start-time $(date -d '1 hour ago' +%s)000 \
        --limit 10 \
        --query 'events[].message' \
        --output text \
        --region $REGION 2>/dev/null || echo "没有找到协调器日志"
}

# 函数：检查告警状态
check_alarm_status() {
    echo "=== 告警状态 ==="
    
    # 检查测试函数的告警
    aws cloudwatch describe-alarms \
        --alarm-name-prefix "${FUNCTION_NAME}-" \
        --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Reason:StateReason,Updated:StateUpdatedTimestamp}' \
        --output table \
        --region $REGION
    
    echo ""
    # 检查系统健康告警
    aws cloudwatch describe-alarms \
        --alarm-name-prefix "lambda-auto-repair-" \
        --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Reason:StateReason}' \
        --output table \
        --region $REGION
}

# 主监控循环
main_monitor() {
    while true; do
        clear
        echo "=== Lambda自动修复系统实时监控 ==="
        echo "时间: $(date)"
        echo "按 Ctrl+C 退出监控"
        echo "================================"
        
        check_system_components
        echo ""
        
        check_alarm_status
        echo ""
        
        view_diagnosis_records
        echo ""
        
        view_repair_records
        echo ""
        
        view_step_functions_history
        echo ""
        
        echo "=== 下次更新: 30秒后 ==="
        sleep 30
    done
}

# 检查命令行参数
case "${1:-monitor}" in
    "components")
        check_system_components
        ;;
    "diagnosis")
        view_diagnosis_records
        ;;
    "repairs")
        view_repair_records
        ;;
    "metrics")
        view_cloudwatch_metrics
        ;;
    "stepfunctions")
        view_step_functions_history
        ;;
    "logs")
        view_system_logs
        ;;
    "alarms")
        check_alarm_status
        ;;
    "monitor"|*)
        main_monitor
        ;;
esac