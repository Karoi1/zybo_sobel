import cv2

# 1. 读取图像
img = cv2.imread("E:\\vivado project\\pcam-udp\\bluebird.png")

# 2. resize 成 (640, 480)
img_resized = cv2.resize(img, (640, 480))

# 3. 转换为灰度图
img_gray = cv2.cvtColor(img_resized, cv2.COLOR_BGR2GRAY)

# 4. 保存
cv2.imwrite("E:\\vivado project\\pcam-udp\\img_gray_640x480.png", img_gray)

print("已保存为 img_gray_640x480.png")