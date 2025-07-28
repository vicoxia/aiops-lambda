# Lambda自动修复系统测试指南

## 🎯 测试目标

本测试用例演示Lambda自动修复系统的**Step Functions工作流架构**如何：
1. 检测Lambda函数的内存不足问题
2. 通过EventBridge触发Step Functions状态机
3. 使用工作流编排自动诊断问题原因
4. 执行内存增加修复
5. 验证修复效果并发送通知

### 🔄 工作流程

```
CloudWatch告警 → EventBridge → Step Functions状态机 → Lambda函数编排
```

**Step Functions执行步骤：**
1. **ParseAlarmEvent** - 解析CloudWatch告警事件
2. **CollectMetricsAndLogs** - 收集函数指标和日志
3. **DiagnoseIssue** - AI智能诊断问题
4. **DetermineAction** - 决定修复策略
5. **ExecuteRepair** - 执行内存配置修复
6. **VerifyRepair** - 验证修复效果
7. **NotifyResult** - 发送结果通知

## 📋 测试前提条件

确保以下组件已成功部署：
- ✅ lambda-auto-repair-main-dev (主基础设施)
- ✅ lambda-auto-repair-functions-dev (Lambda函数和工作流)
- ✅ lambda-auto-repair-monitoring-dev (监控和告警)

## 🚀 完整测试流程

### 步骤1: 部署测试函数

```bash
./test-case/deploy-test-function.sh
```

这将创建一个名为 `lambda-auto-repair-test-function` 的测试函数，配置为：
- 内存: 128MB (故意设置较低)
- 超时: 30秒
- 环境变量: 配置为消耗150MB内存

### 步骤2: 创建监控告警

```bash
./test-case/create-test-alarm.sh
```

这将为测试函数创建三个CloudWatch告警：
- Duration告警 (持续时间 > 25秒)
- Errors告警 (错误数 > 0)
- Throttles告警 (限流数 > 0)

### 步骤3: 启动系统监控 (可选)

在新的终端窗口中运行：

```bash
./test-case/monitor-system.sh
```

这将实时显示系统状态，包括：
- 系统组件状态
- 告警状态
- 诊断和修复记录
- Step Functions执行历史

### 步骤4: 触发测试并观察自动修复

```bash
./test-case/trigger-test.sh
```

这个脚本将：
1. 显示函数初始配置 (128MB内存)
2. 调用测试函数触发内存不足问题
3. 等待告警触发
4. 监控自动修复过程
5. 验证修复结果

## 📊 预期测试结果

### 成功的自动修复流程应该显示：

1. **初始状态**:
   ```
   MemorySize: 128
   ```

2. **函数调用失败**:
   ```
   statusCode: 500
   error: "JavaScript heap out of memory" 或类似错误
   ```

3. **告警触发**:
   ```
   State: ALARM
   Reason: "Threshold Crossed"
   ```

4. **自动修复执行**:
   - 系统检测到告警
   - 收集指标和日志数据
   - Bedrock诊断确认内存问题
   - 执行内存增加 (通常增加到256MB或更高)

5. **修复后状态**:
   ```
   MemorySize: 256 (或更高)
   ```

6. **验证成功**:
   ```
   statusCode: 200
   message: "Function completed successfully"
   ```

## 🔍 监控和调试

### 查看特定组件状态

```bash
# 查看系统组件
./test-case/monitor-system.sh components

# 查看诊断记录
./test-case/monitor-system.sh diagnosis

# 查看修复记录
./test-case/monitor-system.sh repairs

# 查看告警状态
./test-case/monitor-system.sh alarms

# 查看Step Functions执行
./test-case/monitor-system.sh stepfunctions

# 查看系统日志
./test-case/monitor-system.sh logs
```

### 重要日志位置

1. **测试函数日志**:
   ```
   /aws/lambda/lambda-auto-repair-test-function
   ```

2. **协调器函数日志**:
   ```
   /aws/lambda/lambda-auto-repair-coordinator-dev
   ```

3. **其他系统组件日志**:
   ```
   /aws/lambda/lambda-auto-repair-data-collector-dev
   /aws/lambda/lambda-auto-repair-diagnosis-dev
   /aws/lambda/lambda-auto-repair-executor-dev
   /aws/lambda/lambda-auto-repair-verifier-dev
   ```

### DynamoDB表数据

1. **诊断记录表**:
   ```
   lambda-auto-repair-diagnosis-dev
   ```

2. **修复记录表**:
   ```
   lambda-auto-repair-repairs-dev
   ```

## 🛠️ 故障排除

### 常见问题和解决方案

1. **告警未触发**:
   - 检查函数是否真的失败了
   - 确认告警阈值设置正确
   - 等待足够时间让指标生成

2. **自动修复未执行**:
   - 检查EventBridge规则是否启用
   - 确认Lambda函数有正确的权限
   - 查看协调器函数日志

3. **Bedrock诊断失败**:
   - 确认Bedrock服务在当前区域可用
   - 检查模型访问权限
   - 查看诊断函数日志

4. **内存修复失败**:
   - 检查Lambda更新权限
   - 确认目标函数存在且可访问
   - 查看修复执行器日志

### 手动验证步骤

1. **检查函数配置**:
   ```bash
   aws lambda get-function-configuration \
     --function-name lambda-auto-repair-test-function \
     --query '{MemorySize:MemorySize,LastModified:LastModified}'
   ```

2. **查看告警历史**:
   ```bash
   aws cloudwatch describe-alarm-history \
     --alarm-name lambda-auto-repair-test-function-duration-alarm \
     --max-records 5
   ```

3. **检查Step Functions执行**:
   ```bash
   aws stepfunctions list-executions \
     --state-machine-arn "arn:aws:states:us-east-1:ACCOUNT:stateMachine:lambda-auto-repair-workflow-dev" \
     --max-items 5
   ```

## 🧹 清理测试资源

测试完成后，清理创建的资源：

```bash
# 删除测试函数
aws lambda delete-function --function-name lambda-auto-repair-test-function

# 删除告警
aws cloudwatch delete-alarms \
  --alarm-names \
    "lambda-auto-repair-test-function-duration-alarm" \
    "lambda-auto-repair-test-function-errors-alarm" \
    "lambda-auto-repair-test-function-throttles-alarm"

# 删除IAM角色 (如果需要)
aws iam detach-role-policy \
  --role-name lambda-test-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam delete-role --role-name lambda-test-execution-role
```

## 📈 测试变体

### 测试不同场景

1. **超时场景**:
   ```bash
   aws lambda update-function-configuration \
     --function-name lambda-auto-repair-test-function \
     --environment Variables='{MEMORY_TO_CONSUME="100",SHOULD_TIMEOUT="true"}'
   ```

2. **更高内存消耗**:
   ```bash
   aws lambda update-function-configuration \
     --function-name lambda-auto-repair-test-function \
     --environment Variables='{MEMORY_TO_CONSUME="200",SHOULD_TIMEOUT="false"}'
   ```

3. **重置为低内存测试**:
   ```bash
   aws lambda update-function-configuration \
     --function-name lambda-auto-repair-test-function \
     --memory-size 128
   ```

## 📞 支持

如果测试过程中遇到问题：

1. 检查CloudFormation堆栈状态
2. 查看相关CloudWatch日志
3. 验证IAM权限配置
4. 确认AWS服务配额限制

测试成功完成后，你将看到Lambda自动修复系统的完整工作流程！