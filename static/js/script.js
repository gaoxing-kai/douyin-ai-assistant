document.addEventListener('DOMContentLoaded', function() {
    // 初始化Socket.IO
    const socket = io();
    
    // 全局变量
    let audioContext;
    let audioQueue = [];
    let isPlaying = false;
    let commentCount = 0;
    let replyCount = 0;
    let voiceCount = 0;
    
    // 连接WebSocket
    socket.on('connect', () => {
        console.log('Connected to WebSocket server');
    });
    
    // 处理新评论
    socket.on('new_comment', (data) => {
        commentCount++;
        updateStats();
        
        // 添加到评论列表
        const commentElement = createCommentElement(data.user, data.content, data.timestamp);
        document.getElementById('comments-list').prepend(commentElement);
        
        // 移除空状态
        const emptyState = document.querySelector('.comments-list .empty-state');
        if (emptyState) emptyState.remove();
        
        // 使用AI分析评论
        analyzeComment(data.content);
    });
    
    // 系统消息
    socket.on('system_message', (data) => {
        console.log('System message:', data.message);
    });
    
    // 启动直播间
    document.getElementById('start-live')?.addEventListener('click', () => {
        fetch('/start_live')
            .then(response => response.json())
            .then(data => {
                if (data.status === 'success') {
                    document.getElementById('start-live').disabled = true;
                    document.getElementById('stop-live').disabled = false;
                    
                    // 清空评论列表
                    document.getElementById('comments-list').innerHTML = `
                        <div class="empty-state">
                            <i class="fas fa-sync fa-spin"></i>
                            <p>正在连接直播间，请稍候...</p>
                        </div>
                    `;
                }
            });
    });
    
    // 停止直播间
    document.getElementById('stop-live')?.addEventListener('click', () => {
        fetch('/stop_live')
            .then(response => response.json())
            .then(data => {
                if (data.status === 'success') {
                    document.getElementById('start-live').disabled = false;
                    document.getElementById('stop-live').disabled = true;
                    
                    // 显示停止状态
                    document.getElementById('comments-list').innerHTML = `
                        <div class="empty-state">
                            <i class="fas fa-comment-slash"></i>
                            <p>直播间已停止</p>
                        </div>
                    `;
                }
            });
    });
    
    // 测试语音
    document.getElementById('test-voice')?.addEventListener('click', () => {
        const testText = "欢迎使用抖音直播间AI助手，系统运行正常。";
        const voiceStyle = document.getElementById('voice-style')?.value || '知性女声';
        playTextAsSpeech(testText, voiceStyle);
    });
    
    // 保存设置
    document.getElementById('save-settings')?.addEventListener('click', () => {
        const settings = {
            live_url: document.getElementById('live-url').value,
            prompt: document.getElementById('ai-prompt').value,
            voice_style: document.getElementById('voice-style').value
        };
        
        fetch('/settings', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(settings)
        })
        .then(response => response.json())
        .then(data => {
            if (data.status === 'success') {
                alert('设置保存成功！');
            }
        });
    });
    
    // 语音控制
    document.getElementById('volume-control')?.addEventListener('input', (e) => {
        // 这里可以控制音频播放的音量
        console.log('Volume changed to:', e.target.value);
    });
    
    // 创建评论元素
    function createCommentElement(user, content, timestamp) {
        const element = document.createElement('div');
        element.className = 'comment';
        element.innerHTML = `
            <div class="header">
                <span class="user">${user}</span>
                <span class="time">${timestamp}</span>
            </div>
            <div class="content">${content}</div>
        `;
        return element;
    }
    
    // 创建AI回复元素
    function createAIResponseElement(content) {
        const element = document.createElement('div');
        element.className = 'comment ai-response';
        element.innerHTML = `
            <div class="header">
                <span class="user">AI助手</span>
                <span class="time">${new Date().toLocaleTimeString()}</span>
            </div>
            <div class="content">${content}</div>
        `;
        return element;
    }
    
    // 分析评论
    function analyzeComment(comment) {
        // 在实际应用中，这里应该调用后端API
        // 这里使用模拟响应
        setTimeout(() => {
            const prompt = document.getElementById('ai-prompt')?.value || 
                "你是一个专业的直播助手，请用简洁的语言回复观众的问题";
            
            const response = "感谢您的提问！我们的产品采用最新技术制造，质量有保证，提供一年质保。";
            
            // 添加到评论列表
            document.getElementById('comments-list').prepend(createAIResponseElement(response));
            
            // 更新统计
            replyCount++;
            updateStats();
            
            // 显示在预览区
            document.getElementById('ai-preview').innerHTML = `<p>${response}</p>`;
            
            // 语音播报
            const voiceStyle = document.getElementById('voice-style')?.value || '知性女声';
            playTextAsSpeech(response, voiceStyle);
        }, 3000);
    }
    
    // 播放文本语音
    function playTextAsSpeech(text, voiceStyle) {
        // 在实际应用中，这里应该调用后端API获取语音数据
        // 这里使用模拟
        console.log(`Synthesizing: "${text}" with voice: ${voiceStyle}`);
        
        // 模拟语音数据
        const audioData = "simulated_audio_data";
        
        // 添加到播放队列
        audioQueue.push({
            text: text,
            audioData: audioData
        });
        
        // 如果没有在播放，开始播放
        if (!isPlaying) {
            playNextAudio();
        }
    }
    
    // 播放队列中的下一个音频
    function playNextAudio() {
        if (audioQueue.length === 0) {
            isPlaying = false;
            return;
        }
        
        isPlaying = true;
        const audioItem = audioQueue.shift();
        
        // 在实际应用中，这里应该播放真实的音频
        console.log(`Playing audio: ${audioItem.text}`);
        
        // 更新统计
        voiceCount++;
        updateStats();
        
        // 模拟播放时间
        setTimeout(() => {
            playNextAudio();
        }, 2000);
    }
    
    // 更新统计信息
    function updateStats() {
        document.getElementById('comment-count').textContent = commentCount;
        document.getElementById('reply-count').textContent = replyCount;
        document.getElementById('voice-count').textContent = voiceCount;
    }
    
    // 音量值显示
    const voiceSpeed = document.getElementById('voice-speed');
    const speedValue = document.getElementById('speed-value');
    if (voiceSpeed && speedValue) {
        speedValue.textContent = voiceSpeed.value;
        voiceSpeed.addEventListener('input', () => {
            speedValue.textContent = voiceSpeed.value;
        });
    }
    
    const voiceVolume = document.getElementById('voice-volume');
    const volumeValue = document.getElementById('volume-value');
    if (voiceVolume && volumeValue) {
        volumeValue.textContent = voiceVolume.value;
        voiceVolume.addEventListener('input', () => {
            volumeValue.textContent = voiceVolume.value;
        });
    }
    
    // 添加用户模态框
    const addUserModal = document.getElementById('add-user-modal');
    const addUserBtn = document.getElementById('add-user');
    const closeModal = document.querySelector('.modal .close');
    
    if (addUserBtn && addUserModal) {
        addUserBtn.addEventListener('click', () => {
            addUserModal.style.display = 'flex';
        });
        
        closeModal.addEventListener('click', () => {
            addUserModal.style.display = 'none';
        });
        
        document.getElementById('cancel-add').addEventListener('click', () => {
            addUserModal.style.display = 'none';
        });
        
        window.addEventListener('click', (e) => {
            if (e.target === addUserModal) {
                addUserModal.style.display = 'none';
            }
        });
    }
    
    // 复制卡密功能
    document.querySelectorAll('.btn-copy').forEach(button => {
        button.addEventListener('click', () => {
            const key = button.getAttribute('data-key');
            navigator.clipboard.writeText(key).then(() => {
                const originalHTML = button.innerHTML;
                button.innerHTML = '<i class="fas fa-check"></i> 已复制';
                setTimeout(() => {
                    button.innerHTML = originalHTML;
                }, 2000);
            });
        });
    });
});