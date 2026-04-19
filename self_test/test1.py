import time

# 模拟一个耗时约60秒的任务
total_steps = 100
for i in range(total_steps + 1):
    # \r 将光标移回行首，end='' 防止自动换行
    # 这样就可以不断覆盖同一行，形成动态效果
    print(f'\r加载进度: {i:3d}% |' + '█' * i + '-' * (total_steps - i) + '|', end='', flush=True)
    time.sleep(1) # 每次循环暂停1秒，总共约60秒

print() # 循环结束后换行，保持控制台整洁
