/**
 * 测试用Lambda函数 - 模拟内存不足问题
 * 这个函数会故意消耗大量内存来触发自动修复系统
 */

exports.handler = async (event) => {
    console.log('Test function started - simulating memory exhaustion');
    
    // 获取环境变量来控制内存消耗
    const memoryToConsume = parseInt(process.env.MEMORY_TO_CONSUME || '100'); // MB
    const shouldTimeout = process.env.SHOULD_TIMEOUT === 'true';
    
    try {
        // 模拟内存密集型操作
        console.log(`Attempting to consume ${memoryToConsume}MB of memory`);
        
        const arrays = [];
        const chunkSize = 1024 * 1024; // 1MB chunks
        
        for (let i = 0; i < memoryToConsume; i++) {
            // 创建1MB的数组
            const chunk = new Array(chunkSize / 4).fill(Math.random());
            arrays.push(chunk);
            
            // 每10MB输出一次进度
            if (i % 10 === 0) {
                console.log(`Consumed ${i}MB of memory so far`);
            }
            
            // 如果设置了超时标志，添加延迟
            if (shouldTimeout && i > 50) {
                await new Promise(resolve => setTimeout(resolve, 100));
            }
        }
        
        console.log(`Successfully consumed ${memoryToConsume}MB of memory`);
        
        // 模拟一些处理时间
        await new Promise(resolve => setTimeout(resolve, 1000));
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Function completed successfully',
                memoryConsumed: `${memoryToConsume}MB`,
                timestamp: new Date().toISOString()
            })
        };
        
    } catch (error) {
        console.error('Error in test function:', error);
        
        return {
            statusCode: 500,
            body: JSON.stringify({
                error: error.message,
                timestamp: new Date().toISOString()
            })
        };
    }
};