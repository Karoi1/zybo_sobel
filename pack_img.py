import cv2

# 1. 读取灰度图
img = cv2.imread("E:\\vivado project\\pcam-udp\\img_gray_640x480.png", cv2.IMREAD_GRAYSCALE)
assert img.shape == (480, 640), f"Image shape {img.shape}, expected (480, 640)"

# 2. 打包为 32-bit 字: 4 像素/字, LSB=最左像素
#    beat[7:0]=pix[col+0], [15:8]=pix[col+1], [23:16]=pix[col+2], [31:24]=pix[col+3]
words = []
for row in range(480):
    for col in range(0, 640, 4):
        b0 = int(img[row, col + 0])
        b1 = int(img[row, col + 1])
        b2 = int(img[row, col + 2])
        b3 = int(img[row, col + 3])
        word = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
        words.append(word)

# 3. 写 input.hex (每行 1 个 32-bit hex, 供 $readmemh)
out_path = "E:\\vivado project\\pcam-udp\\input.hex"
with open(out_path, "w") as f:
    for w in words:
        f.write(f"{w:08X}\n")

print(f"Wrote {len(words)} words ({480} rows x {640//4} beats) → {out_path}")
