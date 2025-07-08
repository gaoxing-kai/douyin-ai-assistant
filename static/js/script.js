document.addEventListener('DOMContentLoaded', function() {
    // 初始化Socket.IO
    const socket = io();
    
    // 全局状态
    const state = {
        commentCount: 0,
        replyCount: 0,
        voiceCount: 0,
        viewerCount: 0,
        audioQueue: [],  // 语音播放队列
        isPlaying: false,  // 是否正在播放语音
        commentFilter: 'all'  // 评论过滤条件
    };

    // 页面初始化
    initPage();

    // 根据当前页面初始化功能
    function initPage() {
        const path = window.location.pathname;
        if (path.includes('dashboard')) {
            initDashboard();
        } else if (path.includes('users')) {
            initUserManagement();
        } else if (path.includes('keys')) {
            initKeyManagement();
        }
    }

    // 控制面板初始化
    function initDashboard() {
        // 启动/停止直播
        document.getElementById('start-live').addEventListener('click', startLive);
        document.getElementById('stop-live').addEventListener('click', stopLive);
        
        // 测试语音
        document.getElementById('test-voice').addEventListener('click', testVoice);
        
        // 重置统计
        document.getElementById('reset-stats').addEventListener('click', resetStats);
        
        // 评论过滤
        document.getElementById('comment-filter').addEventListener('change', function() {
            state.commentFilter = this.value;
            filterComments();
        });
        
        // 语音音量控制
        document.getElementById('volume-control').addEventListener('input', function() {
            const volume = this.value / 100;
            // 调整所有音频的音量
            document.querySelectorAll('audio').forEach(audio => {
                audio.volume = volume;
            });
        });
    }

    // 用户管理页面初始化
    function initUserManagement() {
        // 添加用户模态框
        const addModal = document.getElementById('add-user-modal');
        document.getElementById('add-user').addEventListener('click', () => {
            addModal.classList.add('show');
        });
        
        // 关闭模态框
        document.querySelectorAll('.close, #cancel-add').forEach(elem => {
            elem.addEventListener('click', () => {
                addModal.classList.remove('show');
            });
        });
        
        // 提交添加用户
        document.getElementById('confirm-add').addEventListener('click', addUser);
        
        // 删除用户
        document.querySelectorAll('.delete-user').forEach(btn => {
            btn.addEventListener('click', function() {
                const userId = this.getAttribute('data-id');
                if (confirm('确定要删除此用户吗？')) {
                    deleteUser(userId);
                }
            });
        });
    }

    // 卡密管理页面初始化
    function initKeyManagement() {
        // 复制卡密
        document.querySelectorAll('.btn-copy').forEach(btn => {
            btn.addEventListener('click', function() {
                const key = this.getAttribute('data-key');
                navigator.clipboard.writeText(key).then(() => {
                    const original = this.innerHTML;
                    this.innerHTML = '<i class="fas fa-check"></i> 已复制';
                    setTimeout(() => this.innerHTML = original, 2000);
                });
            });
        });
        
        // 删除卡密
        document.querySelectorAll('.delete-key').forEach(btn => {
            btn.addEventListener('click', function() {
                const keyId = this.getAttribute('data-id');
                if (confirm('确定要删除此卡密吗？')) {
                    deleteKey(keyId);
                }
            });
        });
    }

    // 启动直播
    function startLive() {
        fetch('/live/start')
            .then(res => res.json())
            .then(data => {
                if (data.status === 'success') {
                    document.getElementById('start-live').disabled = true;
                    document.getElementById('stop-live').disabled = false;
                    document.querySelector('.comments-list').innerHTML = `
                        <div class="empty-state">
                            <i class="fas fa-sync fa-spin"></i>
                            <p>正在接收评论...</p>
                        </div>
                    `;
                    showToast('直播间已启动');
                }
            });
    }

    // 停止直播
    function stopLive() {
        fetch('/live/stop')
            .then(res => res.json())
            .then(data => {
                if (data.status === 'success') {
                    document.getElementById('start-live').disabled = false;
                    document.getElementById('stop-live').disabled = true;
                    showToast('直播间已停止');
                }
            });
    }

    // 测试语音
    function testVoice() {
        const text = "欢迎使用抖音直播间AI助手，当前系统运行正常。";
        playAudio(text, document.getElementById('voice-style').value);
    }

    // 重置统计数据
    function resetStats() {
        state.commentCount = 0;
        state.replyCount = 0;
        state.voiceCount = 0;
        state.viewerCount = 0;
        updateStats();
    }

    // 更新统计数据
    function updateStats() {
        document.getElementById('comment-count').textContent = state.commentCount;
        document.getElementById('reply-count').textContent = state.replyCount;
        document.getElementById('voice-count').textContent = state.voiceCount;
        document.getElementById('viewer-count').textContent = state.viewerCount;
    }

    // WebSocket事件监听
    socket.on('connect', () => {
        console.log('已连接到服务器');
    });

    // 接收新评论
    socket.on('new_comment', (comment) => {
        state.commentCount++;
        state.viewerCount = Math.max(state.viewerCount, Math.floor(Math.random() * 50) + 10); // 模拟观众数
        updateStats();
        
        // 添加评论到列表
        addCommentToDOM(comment, false);
        
        // 触发AI分析
        socket.emit('analyze_comment', comment);
    });

    // 接收AI回复
    socket.on('ai_reply', (reply) => {
        state.replyCount++;
        state.voiceCount++;
        updateStats();
        
        // 添加AI回复到列表
        addCommentToDOM(reply, true);
        
        // 播放语音
        playAudio(reply.content, null, reply.audio_url);
    });

    // 系统消息
    socket.on('system_msg', (msg) => {
        showToast(msg.msg);
    });

    // 添加评论到DOM
    function addCommentToDOM(data, isAI) {
        const list = document.getElementById('comments-list');
        // 移除空状态提示
        const emptyState = list.querySelector('.empty-state');
        if (emptyState) emptyState.remove();
        
        // 创建评论元素
        const div = document.createElement('div');
        div.className = isAI ? 'comment ai-response' : 'comment';
        div.setAttribute('data-answered', isAI);
        div.innerHTML = `
            <div class="header">
                <span class="user">${data.user}</span>
                <span class="time">${data.timestamp}</span>
            </div>
            <div class="content">${data.content}</div>
        `;
        
        // 添加到列表顶部
        list.insertBefore(div, list.firstChild);
        
        // 应用过滤
        filterComments();
    }

    // 评论过滤
    function filterComments() {
        const comments = document.querySelectorAll('.comment');
        comments.forEach(comment => {
            const answered = comment.getAttribute('data-answered') === 'true';
            switch(state.commentFilter) {
                case 'all':
                    comment.style.display = 'block';
                    break;
                case 'answered':
                    comment.style.display = answered ? 'block' : 'none';
                    break;
                case 'unanswered':
                    comment.style.display = !answered ? 'block' : 'none';
                    break;
            }
        });
    }

    // 音频播放队列管理
    function playAudio(text, voiceStyle, audioUrl) {
        // 添加到队列
        state.audioQueue.push({ text, voiceStyle, audioUrl });
        // 如果不在播放中，开始播放
        if (!state.isPlaying) {
            playNextAudio();
        }
    }

    // 播放下一个音频
    function playNextAudio() {
        if (state.audioQueue.length === 0) {
            state.isPlaying = false;
            return;
        }
        
        state.isPlaying = true;
        const { audioUrl } = state.audioQueue.shift();
        
        // 创建音频元素
        const audio = new Audio(audioUrl);
        audio.volume = document.getElementById('volume-control').value / 100;
        audio.play().then(() => {
            // 播放结束后继续下一个
            audio.onended = playNextAudio;
        }).catch(err => {
            console.error('音频播放失败:', err);
            playNextAudio(); // 继续下一个
        });
    }

    // 添加用户
    function addUser() {
        const form = document.getElementById('add-user-form');
        const username = form.querySelector('#new-username').value;
        const password = form.querySelector('#new-password').value;
        const confirmPwd = form.querySelector('#confirm-password').value;
        const isAdmin = form.querySelector('#is-admin').checked;
        
        if (!username || !password) {
            showToast('用户名和密码不能为空', 'error');
            return;
        }
        
        if (password !== confirmPwd) {
            showToast('两次密码不一致', 'error');
            return;
        }
        
        // 提交表单
        const formData = new FormData();
        formData.append('username', username);
        formData.append('password', password);
        formData.append('is_admin', isAdmin);
        
        fetch('/users', {
            method: 'POST',
            body: formData
        }).then(res => res.json())
          .then(data => {
              if (data.status === 'success') {
                  showToast('用户添加成功');
                  document.getElementById('add-user-modal').classList.remove('show');
                  // 刷新页面
                  window.location.reload();
              } else {
                  showToast(data.msg, 'error');
              }
          });
    }

    // 删除用户
    function deleteUser(userId) {
        fetch('/users', {
            method: 'DELETE',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ user_id: userId })
        }).then(res => res.json())
          .then(data => {
              if (data.status === 'success') {
                  showToast('用户已删除');
                  window.location.reload();
              } else {
                  showToast(data.msg, 'error');
              }
          });
    }

    // 删除卡密
    function deleteKey(keyId) {
        fetch('/keys', {
            method: 'DELETE',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ key_id: keyId })
        }).then(res => res.json())
          .then(data => {
              if (data.status === 'success') {
                  showToast('卡密已删除');
                  window.location.reload();
              } else {
                  showToast(data.msg, 'error');
              }
          });
    }

    // 显示提示消息
    function showToast(msg, type = 'info') {
        // 创建toast元素
        const toast = document.createElement('div');
        toast.className = `toast ${type}`;
        toast.style.position = 'fixed';
        toast.style.bottom = '20px';
        toast.style.right = '20px';
        toast.style.padding = '10px 20px';
        toast.style.borderRadius = '4px';
        toast.style.backgroundColor = type === 'error' ? '#ff3860' : '#23d160';
        toast.style.color = 'white';
        toast.style.zIndex = '1000';
        toast.style.animation = 'fadeIn 0.3s, fadeOut 0.3s 2.7s';
        toast.textContent = msg;
        
        document.body.appendChild(toast);
        
        // 3秒后移除
        setTimeout(() => {
            toast.remove();
        }, 3000);
    }

    // 保存设置（通用）
    document.getElementById('save-settings')?.addEventListener('click', function() {
        const form = document.getElementById('settings-form');
        const formData = new FormData(form);
        
        fetch('/settings', {
            method: 'POST',
            body: formData
        }).then(res => res.json())
          .then(data => {
              showToast(data.msg);
          });
    });

    // 语音速度/音量显示同步
    const syncRangeValue = (rangeId, displayId) => {
        const range = document.getElementById(rangeId);
        const display = document.getElementById(displayId);
        if (range && display) {
            display.textContent = range.value;
            range.addEventListener('input', () => {
                display.textContent = range.value;
            });
        }
    };
    
    syncRangeValue('voice-speed', 'speed-value');
    syncRangeValue('voice-volume', 'volume-value');
});