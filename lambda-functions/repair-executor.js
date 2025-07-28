/**
 * Lambda自动修复系统 - 修复执行函数
 * 执行Lambda函数内存配置的修复
 */

// 使用 AWS SDK v3 (Node.js 18 运行时内置)
const { LambdaClient, GetFunctionConfigurationCommand, UpdateFunctionConfigurationCommand } = require('@aws-sdk/client-lambda');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand } = require('@aws-sdk/lib-dynamodb');

const lambda = new LambdaClient({});
const dynamodbClient = new DynamoDBClient({});
const dynamodb = DynamoDBDocumentClient.from(dynamodbClient);

exports.handler = async (event) => {
    console.log('Repair executor function started');
    console.log('Event:', JSON.stringify(event, null, 2));
    
    try {
        const { functionName, memoryIncrease, maxMemory = 3008, dryRun = false } = event;
        
        if (!functionName || !memoryIncrease) {
            throw new Error('functionName and memoryIncrease are required');
        }
        
        console.log(`Executing repair for function: ${functionName}`);
        console.log(`Memory increase: ${memoryIncrease}MB, Max memory: ${maxMemory}MB, Dry run: ${dryRun}`);
        
        // 获取当前函数配置
        const getConfigCommand = new GetFunctionConfigurationCommand({
            FunctionName: functionName
        });
        const currentConfig = await lambda.send(getConfigCommand);
        
        const originalMemory = currentConfig.MemorySize;
        let newMemory = originalMemory + memoryIncrease;
        
        // 确保新内存大小不超过最大限制
        newMemory = Math.min(newMemory, maxMemory);
        
        // 确保内存大小是64的倍数
        newMemory = Math.ceil(newMemory / 64) * 64;
        
        console.log(`Original memory: ${originalMemory}MB, New memory: ${newMemory}MB`);
        
        const repairResult = {
            functionName,
            originalMemory,
            newMemory,
            memoryIncrease: newMemory - originalMemory,
            status: 'success',
            timestamp: new Date().toISOString(),
            dryRun
        };
        
        if (newMemory === originalMemory) {
            repairResult.status = 'skipped';
            repairResult.reason = 'No memory increase needed or already at maximum';
            console.log('No memory change needed');
            return repairResult;
        }
        
        if (dryRun) {
            repairResult.status = 'dry_run';
            repairResult.reason = 'Dry run mode - no actual changes made';
            console.log('Dry run mode - would update memory from', originalMemory, 'to', newMemory);
            return repairResult;
        }
        
        // 执行实际的内存更新
        console.log('Updating Lambda function memory configuration...');
        
        const updateCommand = new UpdateFunctionConfigurationCommand({
            FunctionName: functionName,
            MemorySize: newMemory
        });
        const updateResult = await lambda.send(updateCommand);
        
        console.log('Memory configuration updated successfully');
        console.log('New configuration:', {
            MemorySize: updateResult.MemorySize,
            LastModified: updateResult.LastModified
        });
        
        // 验证更新是否成功
        if (updateResult.MemorySize !== newMemory) {
            throw new Error(`Memory update verification failed. Expected: ${newMemory}, Got: ${updateResult.MemorySize}`);
        }
        
        // 记录修复操作到DynamoDB
        await recordRepairAction(repairResult);
        
        repairResult.lastModified = updateResult.LastModified;
        
        console.log('Repair completed successfully');
        return repairResult;
        
    } catch (error) {
        console.error('Error in repair executor:', error);
        
        // 返回失败结果而不是抛出错误，让调用者处理
        return {
            functionName: event.functionName,
            originalMemory: 0,
            newMemory: 0,
            status: 'failed',
            error: error.message,
            timestamp: new Date().toISOString()
        };
    }
};

async function recordRepairAction(repairResult) {
    try {
        const tableName = process.env.REPAIR_TABLE || 'lambda-auto-repair-repairs-dev';
        
        const record = {
            repairId: `repair-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
            functionName: repairResult.functionName,
            originalMemory: repairResult.originalMemory,
            newMemory: repairResult.newMemory,
            memoryIncrease: repairResult.memoryIncrease,
            status: repairResult.status,
            timestamp: repairResult.timestamp,
            dryRun: repairResult.dryRun || false,
            ttl: Math.floor(Date.now() / 1000) + (90 * 24 * 60 * 60) // 90天后过期
        };
        
        const putCommand = new PutCommand({
            TableName: tableName,
            Item: record
        });
        await dynamodb.send(putCommand);
        
        console.log('Repair action recorded to DynamoDB:', record.repairId);
        
    } catch (error) {
        console.error('Error recording repair action:', error);
        // 不抛出错误，避免影响主要的修复流程
    }
}