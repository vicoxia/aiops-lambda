/**
 * Step Functions适配器函数
 * 将EventBridge事件转换为Step Functions工作流所需的格式
 */

exports.handler = async (event) => {
    console.log('Step Functions adapter started');
    console.log('Input event:', JSON.stringify(event, null, 2));
    
    try {
        // 解析CloudWatch告警事件
        const alarmEvent = parseAlarmEvent(event);
        if (!alarmEvent) {
            throw new Error('Invalid CloudWatch alarm event');
        }
        
        // 转换为Step Functions工作流期望的格式
        const workflowInput = {
            functionName: alarmEvent.functionName,
            alarmName: alarmEvent.alarmName,
            alarmReason: alarmEvent.reason,
            timestamp: alarmEvent.timestamp,
            originalEvent: event
        };
        
        console.log('Transformed input for Step Functions:', JSON.stringify(workflowInput, null, 2));
        return workflowInput;
        
    } catch (error) {
        console.error('Error in Step Functions adapter:', error);
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