import re
import cv2
import numpy as np

BASE = "E:\\vivado project\\pcam-udp"


def _safe_int(s):
    """将字符串安全转为 int，非数字(X/Z/x/z)返回 None"""
    try:
        return int(s)
    except ValueError:
        return None


# ============================================================
# 1. 读取并解析 ctrl_in.txt
# ============================================================
def parse_ctrl_in(path):
    """返回每条记录: (time, s_tvalid, s_tlast, s_tuser, curr_beat, curr_row)
       含 X 的行被跳过"""
    records = []
    skip_x = 0
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) != 6:
                skip_x += 1
                continue
            vals = [_safe_int(p) for p in parts]
            if any(v is None for v in vals):
                skip_x += 1
                continue
            records.append(tuple(vals))
    if skip_x:
        print(f"  ctrl_in.txt: 跳过 {skip_x} 行 (含 X 或格式异常)")
    return records


# ============================================================
# 2. 读取并解析 ctrl_out.txt
# ============================================================
def parse_ctrl_out(path):
    """返回每条记录: (time, tvalid, tlast, tuser)
       含 X 的行被跳过"""
    records = []
    skip_x = 0
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) != 4:
                skip_x += 1
                continue
            vals = [_safe_int(p) for p in parts]
            if any(v is None for v in vals):
                skip_x += 1
                continue
            records.append(tuple(vals))
    if skip_x:
        print(f"  ctrl_out.txt: 跳过 {skip_x} 行 (含 X 或格式异常)")
    return records


# ============================================================
# 3. 读取并解析 pix_out.txt
# ============================================================
def parse_pix(path):
    """返回每条记录: (time, pix3, pix2, pix1, pix0) 十进制
       含 X 的行被跳过"""
    records = []
    skip_x = 0
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) != 5:
                skip_x += 1
                continue
            vals = [_safe_int(p) for p in parts]
            if any(v is None for v in vals):
                skip_x += 1
                continue
            records.append(tuple(vals))
    if skip_x:
        print(f"  pix_out.txt: 跳过 {skip_x} 行 (含 X 或格式异常)")
    return records


# ============================================================
# 4. 输入控制信号检查 (ctrl_in.txt)
# ============================================================
def check_ctrl_in(records):
    """
    records: [(time, s_tvalid, s_tlast, s_tuser, in_beat, in_row), ...]
    """
    errors = []
    records.sort(key=lambda x: x[0])

    # 仅检查 s_tvalid=1 的有效拍
    valid_recs = [(t, l, u, b, r) for t, v, l, u, b, r in records if v == 1]

    tuser_times = [(t, b, r) for t, v, l, u, b, r in records if u == 1 and v == 1]
    tlast_times  = [(t, b, r) for t, v, l, u, b, r in records if l == 1 and v == 1]

    print(f"\n--- 输入控制信号 ---")

    # s_tuser: 恰好 1 次, in_beat=0, in_row=0
    if len(tuser_times) != 1:
        errors.append(f"s_tuser 出现 {len(tuser_times)} 次 (预期 1)")
    else:
        t, b, r = tuser_times[0]
        if b != 0:
            errors.append(f"s_tuser in_beat={b} (预期 0), time={t}")
        if r != 0:
            errors.append(f"s_tuser in_row={r} (预期 0), time={t}")

    # s_tlast: 480 次 (每行 1 次), in_beat=159, in_row=0..479
    for t, b, r in tlast_times:
        if b != 159:
            errors.append(f"s_tlast in_beat={b} (预期 159), time={t}")
        if r < 0 or r > 479:
            errors.append(f"s_tlast in_row={r} 越界, time={t}")

    expected_tlast = 480
    if len(tlast_times) != expected_tlast:
        errors.append(f"s_tlast 总次数={len(tlast_times)} (预期 {expected_tlast})")

    # 总有效拍数
    total_valid = len(valid_recs)
    print(f"  s_tvalid=1 总拍数: {total_valid} (预期 480×160={480*160})")
    if total_valid != 480 * 160:
        errors.append(f"s_tvalid=1 总拍数={total_valid} (预期 {480*160})")

    # 检查 in_beat 序列:
    #   每行内 0→159 递增, tlast 后归 0
    #   in_row 在 tlast 后 +1
    prev_beat = -1
    prev_row  = -1
    for i, (t, l, u, b, r) in enumerate(valid_recs):
        # 行首: in_beat 应为 0
        if b == 0:
            if prev_row == -1:
                # 第一行首拍
                pass
            elif prev_beat != 159:
                errors.append(f"行首 in_beat 归零, 但前拍 in_beat={prev_beat}≠159, time={t}")
        else:
            if b != prev_beat + 1:
                errors.append(f"in_beat 跳跃 {prev_beat}→{b}, time={t}")

        if b == 0 and prev_row != -1:
            if r != prev_row + 1:
                errors.append(f"in_row 跳跃 {prev_row}→{r}, time={t}")

        prev_beat = b
        prev_row  = r

    # 最后一行 in_row 应为 479
    if prev_row != 479:
        errors.append(f"最后一拍 in_row={prev_row} (预期 479)")

    if errors:
        print("  ✗ 输入控制信号错误:")
        for e in errors:
            print(f"    {e}")
    else:
        print("  全部正确 ✓")

    return errors


# ============================================================
# 5. 输出控制信号检查 (ctrl_out.txt)
# ============================================================
def check_ctrl_out(records):
    """records: [(time, tvalid, tlast, tuser), ...] 4字段"""
    errors = []

    records.sort(key=lambda x: x[0])

    # 按时间索引: time → (tvalid, tlast, tuser)
    rec_by_time = {t: (v, l, u) for t, v, l, u in records}

    tuser_recs = [(t, v, l, u) for t, v, l, u in records if u == 1]
    tlast_recs  = [(t, v, l, u) for t, v, l, u in records if l == 1]
    tvalid_high = [(t, v, l, u) for t, v, l, u in records if v == 1]
    tvalid_low  = [(t, v, l, u) for t, v, l, u in records if v == 0]

    # ===== SOF (tuser) 检查 =====
    if not tuser_recs:
        errors.append("tuser (SOF) 从未出现")
    else:
        if len(tuser_recs) > 1:
            errors.append(f"tuser (SOF) 出现 {len(tuser_recs)} 次 (预期 1)")

        t, v, l, u = tuser_recs[0]

        # SOF 哨兵协议: tuser=1 时 tvalid 必须为 0 (axi_signal.md 73-74行)
        if v != 0:
            errors.append(
                f"SOF 协议错误: tuser=1 时 tvalid={v} (预期 0), time={t}. "
                f"S2MM 要求 SOF 哨兵在数据之前发出, 见 axi_signal.md"
            )

        # SOF 下一拍: tvalid 必须为 1, tuser 必须为 0
        times_sorted = sorted(rec_by_time.keys())
        sof_idx = times_sorted.index(t)
        if sof_idx + 1 < len(times_sorted):
            next_t = times_sorted[sof_idx + 1]
            nv, nl, nu = rec_by_time[next_t]
            if nu != 0:
                errors.append(
                    f"SOF 下一拍 tuser={nu} (预期 0), time={next_t}"
                )
            if nv != 1:
                errors.append(
                    f"SOF 下一拍 tvalid={nv} (预期 1), 首像素应在 SOF 下一拍到达, "
                    f"time={next_t}"
                )
        else:
            errors.append("SOF 为最后一拍, 无后续数据")

        print(f"  SOF time={t}, tvalid={v} ✓ (哨兵协议)")

    # ===== tlast 检查 =====
    for t, v, l, u in tlast_recs:
        if v != 1:
            errors.append(f"tlast=1 但 tvalid={v} (预期 1), time={t}")

    expected_tlast = 478
    if len(tlast_recs) != expected_tlast:
        errors.append(f"tlast 总次数={len(tlast_recs)} (预期 {expected_tlast}, 478行)")

    # ===== tvalid 总拍数 =====
    total_valid = len(tvalid_high)
    expected_beats = 478 * 160
    print(f"  tvalid=1 总拍数: {total_valid} (预期 {expected_beats})")
    if total_valid != expected_beats:
        errors.append(f"tvalid=1 总拍数={total_valid} (预期 {expected_beats})")

    if errors:
        print("  ✗ 输出控制信号错误:")
        for e in errors:
            print(f"  ✗ {e}")
    else:
        print("--- 输出控制信号: 全部正确 ✓ ---")

    return errors


# ============================================================
# 6. 像素对比
# ============================================================
def build_output_image(ctrl_records, pix_records):
    """
    从 pix_out.txt 和 ctrl_out.txt 重建输出图像。
    按时间顺序遍历 tvalid=1 的拍, 顺序填充 478×640 图像。
    返回 numpy 数组 (478, 640), dtype=uint8
    """
    # ctrl_records: [(time, tvalid, tlast, tuser), ...] 4字段
    ctrl_by_time = {t: (v, l, u) for t, v, l, u in ctrl_records}
    pix_by_time = {t: (p3, p2, p1, p0) for t, p3, p2, p1, p0 in pix_records}
    common_times = sorted(set(ctrl_by_time.keys()) & set(pix_by_time.keys()))

    out_img = np.zeros((478, 640), dtype=np.uint8)
    out_row, out_beat = 0, 0
    valid_samples = 0
    overflow = 0

    for t in common_times:
        tvalid, tlast, tuser = ctrl_by_time[t]
        if not tvalid:
            continue
        if out_row >= 478:
            overflow += 1
            continue

        valid_samples += 1
        p3, p2, p1, p0 = pix_by_time[t]
        col = out_beat * 4
        out_img[out_row, col + 0] = np.clip(p0, 0, 255)
        out_img[out_row, col + 1] = np.clip(p1, 0, 255)
        out_img[out_row, col + 2] = np.clip(p2, 0, 255)
        out_img[out_row, col + 3] = np.clip(p3, 0, 255)

        out_beat += 1
        if out_beat == 160:
            out_beat = 0
            out_row += 1

    print(f"  tvalid 有效采样: {valid_samples} 拍 (预期 478×160={478*160})")
    if overflow:
        print(f"  超出 478 行溢出: {overflow} 拍 (丢弃)")
    print(f"  输出图像: {out_img.shape[0]} rows x {out_img.shape[1]} cols")
    print(f"  已填充行数: {out_row} / 478")
    return out_img


def sobel_reference(img_gray):
    """
    Python 参考 Sobel: |Gx|+|Gy|, clip [0,255]
    img_gray: (480, 640) uint8 输入
    返回:    (478, 640) uint8, 中心行 = 1..478
    """
    H, W = img_gray.shape
    out = np.zeros((H - 2, W), dtype=np.uint8)
    for r in range(1, H - 1):          # 行 1..478
        for c in range(W):
            p00 = img_gray[r-1, c-1] if c > 0   else 0
            p01 = img_gray[r-1, c]
            p02 = img_gray[r-1, c+1] if c < W-1 else 0
            p10 = img_gray[r,   c-1] if c > 0   else 0
            p11 = img_gray[r,   c]
            p12 = img_gray[r,   c+1] if c < W-1 else 0
            p20 = img_gray[r+1, c-1] if c > 0   else 0
            p21 = img_gray[r+1, c]
            p22 = img_gray[r+1, c+1] if c < W-1 else 0

            gx = int(p02) + 2*int(p12) + int(p22) - int(p00) - 2*int(p10) - int(p20)
            gy = int(p20) + 2*int(p21) + int(p22) - int(p00) - 2*int(p01) - int(p02)

            gx_abs = -gx if gx < 0 else gx
            gy_abs = -gy if gy < 0 else gy
            mag = gx_abs + gy_abs
            out[r-1, c] = np.clip(mag, 0, 255)
    return out


def compare_images(actual, reference, diff_threshold=1):
    """
    比较两幅图像。返回差异统计。
    """
    assert actual.shape == reference.shape, f"shape mismatch: {actual.shape} vs {reference.shape}"

    diff = np.abs(actual.astype(np.int16) - reference.astype(np.int16))
    max_diff = diff.max()
    mean_diff = diff.mean()
    num_diff = (diff > diff_threshold).sum()

    print(f"\n--- 像素对比 ---")
    print(f"  总像素数:     {actual.size}")
    print(f"  Max diff:     {max_diff}")
    print(f"  Mean diff:    {mean_diff:.3f}")
    print(f"  差异 >{diff_threshold} 的像素: {num_diff} ({100*num_diff/actual.size:.2f}%)")

    if num_diff > 0:
        # 定位首个差异像素的行列
        bad_rows, bad_cols = np.where(diff > diff_threshold)
        if len(bad_rows) > 0:
            # 按行分组
            from collections import Counter
            row_counts = Counter(bad_rows)
            worst_rows = row_counts.most_common(5)
            print(f"\n  差异最大的行: {worst_rows}")

            # 检查是否在行首 (beat 0-1 = col 0-7)
            early_cols = sum(1 for c in bad_cols if c < 8)
            late_cols  = sum(1 for c in bad_cols if c >= 632)
            print(f"  其中前 8 列差异: {early_cols}, 后 8 列差异: {late_cols}")

    return max_diff, num_diff


# ============================================================
# 7. Main
# ============================================================
def main():
    ctrl_in_file = f"{BASE}\\ctrl_in.txt"
    ctrl_out_file = f"{BASE}\\ctrl_out.txt"
    pix_file     = f"{BASE}\\pix_out.txt"

    # 输入控制信号
    ctrl_in = parse_ctrl_in(ctrl_in_file)
    print(f"\n读取 ctrl_in.txt:  {len(ctrl_in)} 行")
    check_ctrl_in(ctrl_in)

    # 输出控制信号
    ctrl_out = parse_ctrl_out(ctrl_out_file)
    print(f"读取 ctrl_out.txt: {len(ctrl_out)} 行")
    pix  = parse_pix(pix_file)
    print(f"读取 pix_out.txt:  {len(pix)} 行")

    errors = check_ctrl_out(ctrl_out)

    # 重建输出图像
    actual = build_output_image(ctrl_out, pix)

    # 保存实际输出
    cv2.imwrite(f"{BASE}\\sobel_actual.png", actual)

    # 生成参考 Sobel
    img_gray = cv2.imread(f"{BASE}\\img_gray_640x480.png", cv2.IMREAD_GRAYSCALE)
    reference = sobel_reference(img_gray)
    cv2.imwrite(f"{BASE}\\sobel_reference.png", reference)

    # 对比
    compare_images(actual, reference)

    # 差异图
    diff_img = np.abs(actual.astype(np.int16) - reference.astype(np.int16)).clip(0, 255).astype(np.uint8)
    cv2.imwrite(f"{BASE}\\sobel_diff.png", diff_img)
    print(f"\n输出: sobel_actual.png / sobel_reference.png / sobel_diff.png")


if __name__ == "__main__":
    main()
