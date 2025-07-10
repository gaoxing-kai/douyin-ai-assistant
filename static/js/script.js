/**
 * 全局工具函数
 */
// 显示提示消息
function showToast(message, type = 'info') {
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.style.position = 'fixed';
    toast.style.bottom = '20px';
    toast.style.right = '20px';
    toast.style.padding = '10px 20px';
    toast.style.borderRadius = '4px';
    toast.style.color = 'white';
    toast.style.zIndex = '1000';
    toast.style.animation = 'fadeIn 0.3s, fadeOut 0.3s 2.7s';
    
    // 根据类型设置背景色
    if (type === 'error') {
        toast.style.backgroundColor = '#ff3860';
    } else if (type === 'warning') {
        toast.style.backgroundColor = '#ffdd57';
        toast.style.color = '#333';
    } else {
        toast.style.backgroundColor = '#23d160';
    }
    
    toast.textContent = message;
    document.body.appendChild(toast);
    
    // 3秒后移除
    setTimeout(() => toast.remove(), 3000);
}

/**
 * 用户管理页面脚本
 */
document.addEventListener('DOMContentLoaded', function() {
    // 用户管理页面 - 添加用户弹窗
    if (document.getElementById('add-user')) {
        const modal = document.getElementById('add-user-modal');
        const addBtn = document.getElementById('add-user');
        const closeBtn = document.querySelector('.close');
        const cancelBtn = document.getElementById('cancel-add');
        const confirmBtn = document.getElementById('confirm-add');
        
        // 打开弹窗
        addBtn.addEventListener('click', function() {
            modal.style.display = 'flex';
        });
        
        // 关闭弹窗
        function closeModal() {
            modal.style.display = 'none';
        }
        
        closeBtn.addEventListener('click', closeModal);
        cancelBtn.addEventListener('click', closeModal);
        
        // 点击弹窗外部关闭
        window.addEventListener('click', function(event) {
            if (event.target === modal) {
                closeModal();
            }
        });
        
        // 确认添加用户
        confirmBtn.addEventListener('click', function() {
            const username = document.getElementById('new-username').value;
            const password = document.getElementById('new-password').value;
            const confirmPwd = document.getElementById('confirm-password').value;
            const isAdmin = document.getElementById('is-admin').checked;
            
            if (!username || !password) {
                showToast('用户名和密码不能为空', 'error');
                return;
            }
            
            if (password !== confirmPwd) {
                showToast('两次密码不一致', 'error');
                return;
            }
            
            // 发送请求添加用户
            fetch('/users', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: new URLSearchParams({
                    'username': username,
                    'password': password,
                    'is_admin': isAdmin ? 'on' : ''
                })
            })
            .then(res => res.json())
            .then(data => {
                if (data.status === 'success') {
                    showToast('用户添加成功');
                    closeModal();
                    // 重置表单并刷新页面
                    document.getElementById('add-user-form').reset();
                    setTimeout(() => window.location.reload(), 1000);
                } else {
                    showToast(data.msg, 'error');
                }
            })
            .catch(err => {
                showToast('添加用户失败', 'error');
                console.error(err);
            });
        });
    }
    
    // 用户管理页面 - 删除用户
    document.querySelectorAll('.delete-user').forEach(btn => {
        btn.addEventListener('click', function() {
            const userId = this.getAttribute('data-id');
            if (confirm('确定要删除这个用户吗？')) {
                fetch('/users', {
                    method: 'DELETE',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ user_id: userId })
                })
                .then(res => res.json())
                .then(data => {
                    if (data.status === 'success') {
                        showToast('用户已删除');
                        this.closest('tr').remove();
                    } else {
                        showToast(data.msg, 'error');
                    }
                })
                .catch(err => {
                    showToast('删除用户失败', 'error');
                    console.error(err);
                });
            }
        });
    });
    
    // 卡密管理页面 - 删除卡密
    document.querySelectorAll('.delete-key').forEach(btn => {
        btn.addEventListener('click', function() {
            const keyId = this.getAttribute('data-id');
            if (confirm('确定要删除这个卡密吗？')) {
                fetch('/keys', {
                    method: 'DELETE',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ key_id: keyId })
                })
                .then(res => res.json())
                .then(data => {
                    if (data.status === 'success') {
                        showToast('卡密已删除');
                        this.closest('tr').remove();
                    } else {
                        showToast(data.msg, 'error');
                    }
                })
                .catch(err => {
                    showToast('删除卡密失败', 'error');
                    console.error(err);
                });
            }
        });
    });
    
    // 卡密管理页面 - 复制卡密
    document.querySelectorAll('.btn-copy').forEach(btn => {
        btn.addEventListener('click', function() {
            const key = this.getAttribute('data-key');
            navigator.clipboard.writeText(key)
                .then(() => {
                    const originalText = this.innerHTML;
                    this.innerHTML = '<i class="fas fa-check"></i> 已复制';
                    setTimeout(() => {
                        this.innerHTML = originalText;
                    }, 2000);
                })
                .catch(err => {
                    showToast('复制失败，请手动复制', 'error');
                    console.error(err);
                });
        });
    });
    
    // 设置页面 - 保存设置
    if (document.getElementById('save-settings')) {
        document.getElementById('save-settings').addEventListener('click', function() {
            const form = document.getElementById('settings-form');
            const formData = new FormData(form);
            
            fetch('/settings', {
                method: 'POST',
                body: formData
            })
            .then(res => res.json())
            .then(data => {
                if (data.status === 'success') {
                    showToast('设置已保存');
                } else {
                    showToast(data.msg, 'error');
                }
            })
            .catch(err => {
                showToast('保存设置失败', 'error');
                console.error(err);
            });
        });
    }
    
    // 设置页面 - 音量和语速滑块实时显示
    if (document.getElementById('voice-speed')) {
        const speedSlider = document.getElementById('voice-speed');
        const speedValue = document.getElementById('speed-value');
        const volumeSlider = document.getElementById('voice-volume');
        const volumeValue = document.getElementById('volume-value');
        
        speedSlider.addEventListener('input', function() {
            speedValue.textContent = this.value;
        });
        
        volumeSlider.addEventListener('input', function() {
            volumeValue.textContent = this.value;
        });
    }
});