/**
 * Lambda自动修复系统 - 协调器函数
 * 处理CloudWatch告警事件并协调整个修复流程
 */

// 使用 AWS SDK v3 (Node.js 18 运行时内置)
const { LambdaClient, InvokeCommand } = require('@aws-sdk/client-lambda');
const { SNSClient, PublishCommand } = require('@aws-sdk/client-sns');

const lambda = new LambdaClient({});
const sns = new SNSClient({});

exports.handler = async (event) => {
    console.log('Coordinator function started');
    console.log('Event received:', JSON.stringify(event, null, 2));
    
    try {
        // 解析CloudWatch告警事件
        const alarmEvent = parseAlarmEvent(event);
        if (!alarmEvent) {
            console.log('Not a valid CloudWatch alarm event, skipping');
            return { statusCode: 200, message: 'Event ignored' };
        }
        
        console.log('Processing alarm:', alarmEvent.alarmName, 'for function:', alarmEvent.functionName);
        
        // 1. 收集数据
        console.log('Step 1: Collecting metrics and logs data...');
        const dataCollectionResult = await collectData(alarmEvent);
        
        // 2. 诊断问题
        console.log('Step 2: Diagnosing the issue...');
        const diagnosisResult = await diagnoseIssue(alarmEvent, dataCollectionResult);
        
        // 3. 如果是内存问题，执行修复
        if (diagnosisResult.isMemoryIssue && diagnosisResult.recommendedMemoryIncrease) {
            console.log('Step 3: Memory issue detected, executing repair...');
            const repairResult = await executeRepair(alarmEvent.functionName, diagnosisResult);
            
            // 4. 验证修复效果
            console.log('Step 4: Verifying repair...');
            const verificationResult = await verifyRepair(alarmEvent.functionName, repairResult);
            
            // 5. 发送通知
            await sendNotification({
                type: 'repair_completed',
                functionName: alarmEvent.functionName,
                alarmName: alarmEvent.alarmName,
                diagnosis: diagnosisResult,
                repair: repairResult,
                verification: verificationResult
            });
            
            return {
                statusCode: 200,
                message: 'Auto-repair completed successfully',
                functionName: alarmEvent.functionName,
                originalMemory: repairResult.originalMemory,
                newMemory: repairResult.newMemory,
                verificationStatus: verificationResult.status
            };
        } else {
            console.log('No memory issue detected or no recommended action');
            await sendNotification({
                type: 'no_action_required',
                functionName: alarmEvent.functionName,
                alarmName: alarmEvent.alarmName,
                diagnosis: diagnosisResult
            });
            
            return {
                statusCode: 200,
                message: 'No action required',
                functionName: alarmEvent.functionName,
                diagnosis: diagnosisResult
            };
        }
        
    } catch (error) {
        console.error('Error in coordinator function:', error);
        
        // 发送错误通知
        await sendNotification({
            type: 'error',
            error: error.message,
            event: event
        });
        
        throw error;
    }
};

function parseAlarmEvent(event) {
    try {
        // 检查是否是CloudWatch告警事件
        if (event.source !== 'aws.cloudwatch' || 
            event['detail-type'] !== 'CloudWatch Alarm State Change') {
            return null;
        }
        
        const detail = event.detail;
        if (detail.state.value !== 'ALARM') {
            return null;
        }
        
        // 从告警名称中提取函数名称
        const alarmName = detail.alarmName;
        let functionName = null;
        
        // 尝试从告警名称中提取函数名称
        const patterns = [
            /^(.+)-(duration|errors|throttles)-alarm$/i,
            /^lambda-(.+)-(duration|errors|throttles)$/i,
            /^(.+)-(alarm)$/i
        ];
        
        for (const pattern of patterns) {
            const match = alarmName.match(pattern);
            if (match) {
                functionName = match[1];
                break;
            }
        }
        
        if (!functionName) {
            console.warn('Could not extract function name from alarm:', alarmName);
            return null;
        }
        
        return {
            alarmName,
            functionName,
            state: detail.state.value,
            reason: detail.state.reason,
            timestamp: detail.state.timestamp
        };
        
    } catch (error) {
        console.error('Error parsing alarm event:', error);
        return null;
    }
}

async function collectData(alarmEvent) {
    try {
        const params = {
            FunctionName: process.env.DATA_COLLECTOR_FUNCTION,
            Payload: JSON.stringify({
                functionName: alarmEvent.functionName,
                alarmName: alarmEvent.alarmName,
                timestamp: alarmEvent.timestamp
            })
        };
        
        const command = new InvokeCommand(params);
        const result = await lambda.send(command);
        const payload = JSON.parse(new TextDecoder().decode(result.Payload));
        
        if (result.FunctionError) {
            throw new Error(`Data collection failed: ${payload.errorMessage || 'Unknown error'}`);
        }
        
        return payload;
    } catch (error) {
        console.error('Error collecting data:', error);
        throw error;
    }
}

async function diagnoseIssue(alarmEvent, dataCollectionResult) {
    try {
        const params = {
            FunctionName: process.env.DIAGNOSIS_FUNCTION,
            Payload: JSON.stringify({
                functionName: alarmEvent.functionName,
                alarmName: alarmEvent.alarmName,
                alarmReason: alarmEvent.reason,
                dataCollection: dataCollectionResult
            })
        };
        
        const command = new InvokeCommand(params);
        const result = await lambda.send(command);
        const payload = JSON.parse(new TextDecoder().decode(result.Payload));
        
        if (result.FunctionError) {
            throw new Error(`Diagnosis failed: ${payload.errorMessage || 'Unknown error'}`);
        }
        
        return payload;
    } catch (error) {
        console.error('Error diagnosing issue:', error);
        throw error;
    }
}

async function executeRepair(functionName, diagnosisResult) {
    try {
        const params = {
            FunctionName: process.env.REPAIR_EXECUTOR_FUNCTION,
            Payload: JSON.stringify({
                functionName,
                memoryIncrease: diagnosisResult.recommendedMemoryIncrease,
                maxMemory: 3008, // Lambda最大内存限制
                dryRun: false
            })
        };
        
        const command = new InvokeCommand(params);
        const result = await lambda.send(command);
        const payload = JSON.parse(new TextDecoder().decode(result.Payload));
        
        if (result.FunctionError) {
            throw new Error(`Repair execution failed: ${payload.errorMessage || 'Unknown error'}`);
        }
        
        return payload;
    } catch (error) {
        console.error('Error executing repair:', error);
        throw error;
    }
}

async function verifyRepair(functionName, repairResult) {
    try {
        const params = {
            FunctionName: process.env.VERIFICATION_FUNCTION,
            Payload: JSON.stringify({
                functionName,
                repairTimestamp: repairResult.timestamp,
                originalMemory: repairResult.originalMemory,
                newMemory: repairResult.newMemory
            })
        };
        
        const command = new InvokeCommand(params);
        const result = await lambda.send(command);
        const payload = JSON.parse(new TextDecoder().decode(result.Payload));
        
        if (result.FunctionError) {
            console.warn('Verification failed, but repair was completed:', payload.errorMessage);
            return { status: 'verification_failed', error: payload.errorMessage };
        }
        
        return payload;
    } catch (error) {
        console.error('Error verifying repair:', error);
        return { status: 'verification_failed', error: error.message };
    }
}

async function sendNotification(notificationData) {
    try {
        const topicArn = process.env.NOTIFICATION_TOPIC || 
                        `arn:aws:sns:${process.env.AWS_REGION}:${process.env.AWS_ACCOUNT_ID}:lambda-auto-repair-notifications-${process.env.ENVIRONMENT}`;
        
        const subject = `Lambda Auto-Repair: ${notificationData.type} - ${notificationData.functionName || 'System'}`;
        const message = JSON.stringify(notificationData, null, 2);
        
        const command = new PublishCommand({
            TopicArn: topicArn,
            Subject: subject,
            Message: message
        });
        await sns.send(command);
        
        console.log('Notification sent successfully');
    } catch (error) {
        console.error('Error sending notification:', error);
        // 不抛出错误，避免影响主流程
    }
}