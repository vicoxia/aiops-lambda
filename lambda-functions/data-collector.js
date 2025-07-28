/**
 * Lambda自动修复系统 - 数据收集函数
 * 收集Lambda函数的指标和日志数据
 */

// 使用 AWS SDK v3 (Node.js 18 运行时内置)
const { CloudWatchClient, GetMetricDataCommand } = require('@aws-sdk/client-cloudwatch');
const { CloudWatchLogsClient, FilterLogEventsCommand, DescribeLogGroupsCommand } = require('@aws-sdk/client-cloudwatch-logs');

const cloudwatch = new CloudWatchClient({});
const cloudwatchlogs = new CloudWatchLogsClient({});

exports.handler = async (event) => {
    console.log('Data collector function started');
    console.log('Event:', JSON.stringify(event, null, 2));
    
    try {
        const { functionName, alarmName, timestamp } = event;
        
        if (!functionName) {
            throw new Error('functionName is required');
        }
        
        const endTime = new Date(timestamp || Date.now());
        const startTime = new Date(endTime.getTime() - 30 * 60 * 1000); // 30分钟前
        
        console.log(`Collecting data for function: ${functionName}`);
        console.log(`Time range: ${startTime.toISOString()} to ${endTime.toISOString()}`);
        
        // 并行收集指标和日志
        const [metrics, logs] = await Promise.all([
            collectMetrics(functionName, startTime, endTime),
            collectLogs(functionName, startTime, endTime)
        ]);
        
        const result = {
            functionName,
            alarmName,
            timestamp: endTime.toISOString(),
            metrics,
            logs,
            collectedAt: new Date().toISOString()
        };
        
        console.log('Data collection completed successfully');
        return result;
        
    } catch (error) {
        console.error('Error in data collector:', error);
        throw error;
    }
};

async function collectMetrics(functionName, startTime, endTime) {
    try {
        const metricQueries = [
            {
                Id: 'duration',
                MetricStat: {
                    Metric: {
                        Namespace: 'AWS/Lambda',
                        MetricName: 'Duration',
                        Dimensions: [{ Name: 'FunctionName', Value: functionName }]
                    },
                    Period: 300,
                    Stat: 'Average'
                }
            },
            {
                Id: 'errors',
                MetricStat: {
                    Metric: {
                        Namespace: 'AWS/Lambda',
                        MetricName: 'Errors',
                        Dimensions: [{ Name: 'FunctionName', Value: functionName }]
                    },
                    Period: 300,
                    Stat: 'Sum'
                }
            },
            {
                Id: 'throttles',
                MetricStat: {
                    Metric: {
                        Namespace: 'AWS/Lambda',
                        MetricName: 'Throttles',
                        Dimensions: [{ Name: 'FunctionName', Value: functionName }]
                    },
                    Period: 300,
                    Stat: 'Sum'
                }
            }
        ];
        
        const params = {
            StartTime: startTime,
            EndTime: endTime,
            MetricDataQueries: metricQueries
        };
        
        const command = new GetMetricDataCommand(params);
        const result = await cloudwatch.send(command);
        
        const processedMetrics = {};
        result.MetricDataResults.forEach(metric => {
            processedMetrics[metric.Id] = {
                values: metric.Values || [],
                timestamps: metric.Timestamps || [],
                average: metric.Values && metric.Values.length > 0 ? 
                    metric.Values.reduce((a, b) => a + b, 0) / metric.Values.length : 0,
                max: metric.Values && metric.Values.length > 0 ? Math.max(...metric.Values) : 0,
                count: metric.Values ? metric.Values.length : 0
            };
        });
        
        console.log('Metrics collected:', Object.keys(processedMetrics));
        return processedMetrics;
        
    } catch (error) {
        console.error('Error collecting metrics:', error);
        return {};
    }
}

async function collectLogs(functionName, startTime, endTime) {
    try {
        const logGroupName = `/aws/lambda/${functionName}`;
        
        // 检查日志组是否存在
        try {
            const describeCommand = new DescribeLogGroupsCommand({
                logGroupNamePrefix: logGroupName
            });
            await cloudwatchlogs.send(describeCommand);
        } catch (error) {
            console.warn(`Log group ${logGroupName} not found or not accessible`);
            return { events: [], summary: 'Log group not accessible' };
        }
        
        const params = {
            logGroupName,
            startTime: startTime.getTime(),
            endTime: endTime.getTime(),
            limit: 100,
            filterPattern: 'ERROR Exception "Task timed out" "Max Memory Used" REPORT'
        };
        
        const filterCommand = new FilterLogEventsCommand(params);
        const result = await cloudwatchlogs.send(filterCommand);
        
        const events = result.events || [];
        const processedLogs = {
            events: events.map(event => ({
                timestamp: new Date(event.timestamp).toISOString(),
                message: event.message,
                logStreamName: event.logStreamName
            })),
            summary: {
                totalEvents: events.length,
                errorCount: events.filter(e => e.message.includes('ERROR')).length,
                timeoutCount: events.filter(e => e.message.includes('Task timed out')).length,
                memoryReports: events.filter(e => e.message.includes('Max Memory Used')).length
            }
        };
        
        // 提取内存使用信息
        const memoryInfo = extractMemoryInfo(events);
        if (memoryInfo) {
            processedLogs.memoryInfo = memoryInfo;
        }
        
        console.log('Logs collected:', processedLogs.summary);
        return processedLogs;
        
    } catch (error) {
        console.error('Error collecting logs:', error);
        return { events: [], summary: 'Error collecting logs', error: error.message };
    }
}

function extractMemoryInfo(events) {
    const memoryReports = events.filter(event => 
        event.message.includes('REPORT') && event.message.includes('Max Memory Used')
    );
    
    if (memoryReports.length === 0) {
        return null;
    }
    
    const memoryData = [];
    
    memoryReports.forEach(report => {
        const message = report.message;
        
        // 提取内存信息
        const memorySizeMatch = message.match(/Memory Size:\s*(\d+)\s*MB/);
        const maxMemoryUsedMatch = message.match(/Max Memory Used:\s*(\d+)\s*MB/);
        const durationMatch = message.match(/Duration:\s*([\d.]+)\s*ms/);
        
        if (memorySizeMatch && maxMemoryUsedMatch) {
            const memorySize = parseInt(memorySizeMatch[1]);
            const maxMemoryUsed = parseInt(maxMemoryUsedMatch[1]);
            const duration = durationMatch ? parseFloat(durationMatch[1]) : null;
            
            memoryData.push({
                timestamp: new Date(report.timestamp).toISOString(),
                memorySize,
                maxMemoryUsed,
                memoryUtilization: Math.round((maxMemoryUsed / memorySize) * 100),
                duration
            });
        }
    });
    
    if (memoryData.length === 0) {
        return null;
    }
    
    // 计算平均值
    const avgUtilization = memoryData.reduce((sum, item) => sum + item.memoryUtilization, 0) / memoryData.length;
    const maxUtilization = Math.max(...memoryData.map(item => item.memoryUtilization));
    const currentMemorySize = memoryData[memoryData.length - 1].memorySize;
    
    return {
        currentMemorySize,
        averageUtilization: Math.round(avgUtilization),
        maxUtilization,
        samples: memoryData.length,
        recentSamples: memoryData.slice(-3) // 最近3个样本
    };
}