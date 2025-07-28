/**
 * Lambda自动修复系统 - 诊断函数
 * 分析收集的数据并诊断是否为内存问题
 * 集成Amazon Bedrock进行智能诊断
 */

// 使用 AWS SDK v3 (Node.js 18 运行时内置)
const { BedrockRuntimeClient, InvokeModelCommand } = require('@aws-sdk/client-bedrock-runtime');

const bedrock = new BedrockRuntimeClient({});

exports.handler = async (event) => {
    console.log('Diagnosis function started');
    console.log('Event:', JSON.stringify(event, null, 2));
    
    try {
        const { functionName, alarmName, alarmReason, dataCollection } = event;
        
        if (!functionName || !dataCollection) {
            throw new Error('functionName and dataCollection are required');
        }
        
        console.log(`Diagnosing issue for function: ${functionName}`);
        console.log(`Alarm: ${alarmName}, Reason: ${alarmReason}`);
        
        // 首先尝试使用Bedrock AI进行智能诊断
        let diagnosis;
        try {
            diagnosis = await performBedrockDiagnosis(functionName, alarmName, alarmReason, dataCollection);
            console.log('Bedrock AI diagnosis completed');
        } catch (error) {
            console.warn('Bedrock diagnosis failed, falling back to rule-based diagnosis:', error.message);
            diagnosis = await performRuleBasedDiagnosis(functionName, alarmName, alarmReason, dataCollection);
        }
        
        console.log('Diagnosis completed:', diagnosis);
        return diagnosis;
        
    } catch (error) {
        console.error('Error in diagnosis function:', error);
        throw error;
    }
};

// Bedrock AI智能诊断函数
async function performBedrockDiagnosis(functionName, alarmName, alarmReason, dataCollection) {
    const modelId = process.env.BEDROCK_MODEL_ID || 'anthropic.claude-3-sonnet-20240229-v1:0';
    
    // 构建诊断提示
    const prompt = buildDiagnosisPrompt(functionName, alarmName, alarmReason, dataCollection);
    
    const params = {
        modelId: modelId,
        contentType: 'application/json',
        accept: 'application/json',
        body: JSON.stringify({
            anthropic_version: "bedrock-2023-05-31",
            max_tokens: 1000,
            messages: [
                {
                    role: "user",
                    content: prompt
                }
            ]
        })
    };
    
    try {
        const command = new InvokeModelCommand(params);
        const response = await bedrock.send(command);
        const responseBody = JSON.parse(new TextDecoder().decode(response.body));
        
        // 解析Bedrock响应并转换为标准诊断格式
        return parseBedrockResponse(responseBody, functionName, alarmName);
        
    } catch (error) {
        console.error('Bedrock diagnosis failed:', error);
        throw error;
    }
}

// 构建Bedrock诊断提示
function buildDiagnosisPrompt(functionName, alarmName, alarmReason, dataCollection) {
    const { metrics, logs } = dataCollection;
    
    let prompt = `You are an AWS Lambda performance expert. Analyze the following Lambda function issue and determine if it's caused by memory insufficiency.

Function: ${functionName}
Alarm: ${alarmName}
Alarm Reason: ${alarmReason}

Metrics Data:
`;
    
    if (metrics.duration) {
        prompt += `- Average Duration: ${metrics.duration.average}ms (Max: ${metrics.duration.max}ms)\n`;
    }
    if (metrics.errors) {
        prompt += `- Errors: ${metrics.errors.count} errors detected\n`;
    }
    if (metrics.throttles) {
        prompt += `- Throttles: ${metrics.throttles.count} throttles detected\n`;
    }
    
    prompt += `\nLog Analysis:`;
    if (logs.summary) {
        prompt += `
- Total Events: ${logs.summary.totalEvents}
- Error Count: ${logs.summary.errorCount}
- Timeout Count: ${logs.summary.timeoutCount}
- Memory Reports: ${logs.summary.memoryReports}
`;
    }
    
    if (logs.memoryInfo) {
        prompt += `
Memory Usage:
- Current Memory Size: ${logs.memoryInfo.currentMemorySize}MB
- Average Utilization: ${logs.memoryInfo.averageUtilization}%
- Max Utilization: ${logs.memoryInfo.maxUtilization}%
- Samples: ${logs.memoryInfo.samples}
`;
    }
    
    if (logs.events && logs.events.length > 0) {
        prompt += `\nRecent Log Events:\n`;
        logs.events.slice(0, 5).forEach(event => {
            prompt += `- ${event.timestamp}: ${event.message.substring(0, 200)}\n`;
        });
    }
    
    prompt += `\nPlease analyze this data and respond with a JSON object containing:
{
  "isMemoryIssue": boolean,
  "confidence": number (0-1),
  "reasoning": "detailed explanation",
  "recommendedMemoryIncrease": number (in MB, must be multiple of 64),
  "evidencePoints": [
    {
      "type": "string",
      "description": "string",
      "weight": number
    }
  ]
}

Focus on memory-related indicators like:
- High memory utilization (>85%)
- Memory-related error patterns
- Duration increases that correlate with memory pressure
- Out of memory errors in logs

Provide specific memory increase recommendations based on current usage patterns.`;
    
    return prompt;
}

// 解析Bedrock响应
function parseBedrockResponse(responseBody, functionName, alarmName) {
    try {
        const content = responseBody.content[0].text;
        
        // 尝试提取JSON响应
        const jsonMatch = content.match(/\{[\s\S]*\}/);
        if (!jsonMatch) {
            throw new Error('No JSON found in Bedrock response');
        }
        
        const aiDiagnosis = JSON.parse(jsonMatch[0]);
        
        // 转换为标准诊断格式
        return {
            functionName,
            alarmName,
            isMemoryIssue: aiDiagnosis.isMemoryIssue || false,
            confidence: Math.round((aiDiagnosis.confidence || 0) * 100) / 100,
            reasoning: aiDiagnosis.reasoning || 'AI diagnosis completed',
            recommendedAction: aiDiagnosis.isMemoryIssue ? 
                `Increase Lambda function memory by ${aiDiagnosis.recommendedMemoryIncrease || 256}MB` : 
                'No action required',
            recommendedMemoryIncrease: aiDiagnosis.recommendedMemoryIncrease || 0,
            evidencePoints: aiDiagnosis.evidencePoints || [],
            timestamp: new Date().toISOString(),
            diagnosisMethod: 'bedrock-ai'
        };
        
    } catch (error) {
        console.error('Error parsing Bedrock response:', error);
        throw new Error('Failed to parse Bedrock diagnosis response');
    }
}

// 基于规则的诊断函数（作为Bedrock的后备方案）
async function performRuleBasedDiagnosis(functionName, alarmName, alarmReason, dataCollection) {
    const { metrics, logs } = dataCollection;
    
    // 初始化诊断结果
    let diagnosis = {
        functionName,
        alarmName,
        isMemoryIssue: false,
        confidence: 0.0,
        reasoning: '',
        recommendedAction: 'No action required',
        recommendedMemoryIncrease: 0,
        evidencePoints: [],
        timestamp: new Date().toISOString()
    };
    
    const evidencePoints = [];
    let memoryIssueScore = 0;
    let totalScore = 0;
    
    // 1. 分析告警类型
    if (alarmName.includes('error') || alarmName.includes('Error')) {
        evidencePoints.push({
            type: 'alarm_type',
            description: 'Error alarm triggered',
            weight: 0.3
        });
        memoryIssueScore += 0.3;
    }
    
    if (alarmName.includes('duration') || alarmName.includes('Duration')) {
        evidencePoints.push({
            type: 'alarm_type',
            description: 'Duration alarm triggered',
            weight: 0.2
        });
        memoryIssueScore += 0.2;
    }
    
    totalScore += 0.3;
    
    // 2. 分析指标数据
    if (metrics.errors && metrics.errors.count > 0) {
        evidencePoints.push({
            type: 'metrics',
            description: `${metrics.errors.count} error(s) detected in recent period`,
            weight: 0.4
        });
        memoryIssueScore += 0.4;
    }
    
    if (metrics.duration && metrics.duration.average > 0) {
        const avgDuration = metrics.duration.average;
        if (avgDuration > 25000) { // 超过25秒
            evidencePoints.push({
                type: 'metrics',
                description: `High average duration: ${Math.round(avgDuration)}ms`,
                weight: 0.3
            });
            memoryIssueScore += 0.3;
        }
    }
    
    totalScore += 0.4;
    
    // 3. 分析日志数据
    if (logs.summary) {
        const { errorCount, timeoutCount, memoryReports } = logs.summary;
        
        if (errorCount > 0) {
            evidencePoints.push({
                type: 'logs',
                description: `${errorCount} error log entries found`,
                weight: 0.2
            });
            memoryIssueScore += 0.2;
        }
        
        if (timeoutCount > 0) {
            evidencePoints.push({
                type: 'logs',
                description: `${timeoutCount} timeout events detected`,
                weight: 0.3
            });
            memoryIssueScore += 0.3;
        }
    }
    
    // 4. 分析内存使用情况
    if (logs.memoryInfo) {
        const { averageUtilization, maxUtilization, currentMemorySize } = logs.memoryInfo;
        
        if (maxUtilization >= 95) {
            evidencePoints.push({
                type: 'memory_analysis',
                description: `Very high memory utilization: ${maxUtilization}%`,
                weight: 0.5
            });
            memoryIssueScore += 0.5;
        } else if (maxUtilization >= 85) {
            evidencePoints.push({
                type: 'memory_analysis',
                description: `High memory utilization: ${maxUtilization}%`,
                weight: 0.3
            });
            memoryIssueScore += 0.3;
        }
        
        // 基于内存使用情况推荐内存增加量
        if (maxUtilization >= 85) {
            let recommendedIncrease = 0;
            
            if (maxUtilization >= 95) {
                // 非常高的使用率，建议增加50%或至少256MB
                recommendedIncrease = Math.max(Math.round(currentMemorySize * 0.5), 256);
            } else if (maxUtilization >= 90) {
                // 高使用率，建议增加30%或至少128MB
                recommendedIncrease = Math.max(Math.round(currentMemorySize * 0.3), 128);
            } else {
                // 中等使用率，建议增加20%或至少128MB
                recommendedIncrease = Math.max(Math.round(currentMemorySize * 0.2), 128);
            }
            
            // 确保增加量是64的倍数（Lambda内存配置要求）
            recommendedIncrease = Math.ceil(recommendedIncrease / 64) * 64;
            
            diagnosis.recommendedMemoryIncrease = recommendedIncrease;
        }
    }
    
    totalScore += 0.3;
    
    // 5. 分析日志中的特定错误模式
    const errorPatterns = [
        'JavaScript heap out of memory',
        'Cannot allocate memory',
        'OutOfMemoryError',
        'Runtime exited with error: signal: killed'
    ];
    
    let memoryErrorFound = false;
    if (logs.events) {
        for (const event of logs.events) {
            for (const pattern of errorPatterns) {
                if (event.message.includes(pattern)) {
                    evidencePoints.push({
                        type: 'error_pattern',
                        description: `Memory-related error detected: ${pattern}`,
                        weight: 0.6
                    });
                    memoryIssueScore += 0.6;
                    memoryErrorFound = true;
                    break;
                }
            }
            if (memoryErrorFound) break;
        }
    }
    
    // 6. 计算最终置信度
    const confidence = totalScore > 0 ? Math.min(memoryIssueScore / totalScore, 1.0) : 0;
    
    // 7. 确定是否为内存问题
    const isMemoryIssue = confidence >= 0.6 || memoryErrorFound;
    
    // 8. 生成推理说明
    let reasoning = '';
    if (isMemoryIssue) {
        reasoning = `Memory issue detected with ${Math.round(confidence * 100)}% confidence. `;
        reasoning += `Key indicators: ${evidencePoints.map(ep => ep.description).join(', ')}.`;
        
        if (diagnosis.recommendedMemoryIncrease > 0) {
            reasoning += ` Recommended to increase memory by ${diagnosis.recommendedMemoryIncrease}MB.`;
        }
    } else {
        reasoning = `No clear memory issue detected (${Math.round(confidence * 100)}% confidence). `;
        reasoning += `The issue may be related to code logic, external dependencies, or other factors.`;
    }
    
    // 9. 确定推荐操作
    let recommendedAction = 'No action required';
    if (isMemoryIssue && diagnosis.recommendedMemoryIncrease > 0) {
        recommendedAction = `Increase Lambda function memory by ${diagnosis.recommendedMemoryIncrease}MB`;
    } else if (isMemoryIssue) {
        recommendedAction = 'Manual investigation required - memory issue detected but unable to determine optimal memory increase';
    } else {
        recommendedAction = 'Manual investigation required - issue does not appear to be memory-related';
    }
    
    // 10. 如果没有推荐的内存增加量但检测到内存问题，提供默认建议
    if (isMemoryIssue && diagnosis.recommendedMemoryIncrease === 0) {
        // 基于当前内存大小提供默认建议
        if (logs.memoryInfo && logs.memoryInfo.currentMemorySize) {
            const currentMemory = logs.memoryInfo.currentMemorySize;
            const defaultIncrease = Math.max(Math.round(currentMemory * 0.5), 256);
            diagnosis.recommendedMemoryIncrease = Math.ceil(defaultIncrease / 64) * 64;
        } else {
            // 如果无法获取当前内存大小，使用默认值
            diagnosis.recommendedMemoryIncrease = 256;
        }
    }
    
    // 更新诊断结果
    diagnosis.isMemoryIssue = isMemoryIssue;
    diagnosis.confidence = Math.round(confidence * 100) / 100; // 保留2位小数
    diagnosis.reasoning = reasoning;
    diagnosis.recommendedAction = recommendedAction;
    diagnosis.evidencePoints = evidencePoints;
    
    return diagnosis;
}