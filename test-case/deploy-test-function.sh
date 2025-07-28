#!/bin/bash

# 部署测试Lambda函数的脚本
# 用于测试Lambda自动修复系统

set -e

# 配置参数
FUNCTION_NAME="lambda-auto-repair-test-function"
ENVIRONMENT="dev"
REGION="us-east-1"
INITIAL_MEMORY=128  # 故意设置较低的内存来触发问题
TIMEOUT=30

echo "=== 部署测试Lambda函数 ==="
echo "函数名称: $FUNCTION_NAME"
echo "环境: $ENVIRONMENT"
echo "区域: $REGION"
echo "初始内存: ${INITIAL_MEMORY}MB"
echo "超时时间: ${TIMEOUT}秒"
echo "================================"

# 创建部署包
echo "创建部署包..."
zip -r test-function.zip memory-exhaustion-function.js

# 检查函数是否已存在
if aws lambda get-function --function-name $FUNCTION_NAME --region $REGION >/dev/null 2>&1; then
    echo "函数已存在，更新代码..."
    aws lambda update-function-code \
        --function-name $FUNCTION_NAME \
        --zip-file fileb://test-function.zip \
        --region $REGION
    
    echo "更新函数配置..."
    aws lambda update-function-configuration \
        --function-name $FUNCTION_NAME \
        --memory-size $INITIAL_MEMORY \
        --timeout $TIMEOUT \
        --environment Variables='{MEMORY_TO_CONSUME="150",SHOULD_TIMEOUT="false"}' \
        --region $REGION
else
    echo "创建新的Lambda函数..."
    
    # 创建执行角色（如果不存在）
    ROLE_NAME="lambda-test-execution-role"
    ROLE_ARN="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/$ROLE_NAME"
    
    if ! aws iam get-role --role-name $ROLE_NAME >/dev/null 2>&1; then
        echo "创建IAM执行角色..."
        aws iam create-role \
            --role-name $ROLE_NAME \
            --assume-role-policy-document '{
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
            }'
        
        aws iam attach-role-policy \
            --role-name $ROLE_NAME \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        echo "等待角色创建完成..."
        sleep 10
    fi
    
    # 创建Lambda函数
    aws lambda create-function \
        --function-name $FUNCTION_NAME \
        --runtime nodejs18.x \
        --role $ROLE_ARN \
        --handler memory-exhaustion-function.handler \
        --zip-file fileb://test-function.zip \
        --memory-size $INITIAL_MEMORY \
        --timeout $TIMEOUT \
        --environment Variables='{MEMORY_TO_CONSUME="150",SHOULD_TIMEOUT="false"}' \
        --region $REGION
fi

echo "函数部署完成！"

# 清理临时文件
rm -f test-function.zip

echo ""
echo "=== 下一步 ==="
echo "1. 运行 ./test-case/create-test-alarm.sh 创建CloudWatch告警"
echo "2. 运行 ./test-case/trigger-test.sh 触发测试"
echo "3. 监控自动修复过程"