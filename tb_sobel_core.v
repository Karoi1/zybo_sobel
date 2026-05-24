`timescale 1ns / 1ps

module tb_sobel_core;

    // ==========================================================
    // 时钟与复位
    // ==========================================================
    reg clk = 1;
    reg rst_n = 0;
    always #5 clk = ~clk;           // 100 MHz, period=10ns

    // ==========================================================
    // S_AXIS 驱动 (模拟 VDMA M_AXIS_MM2S)
    // ==========================================================
    reg  [31:0] s_axis_tdata;
    reg         s_axis_tvalid;
    reg         s_axis_tlast;
    reg         s_axis_tuser;
    wire        s_axis_tready;

    // ==========================================================
    // M_AXIS 接收 (模拟 VDMA S_AXIS_S2MM)
    // ==========================================================
    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    wire        m_axis_tlast;
    wire        m_axis_tuser;
    reg         m_axis_tready = 1'd1;

    // ==========================================================
    // sobel_core 例化
    // ==========================================================
    sobel_core #(
        .H_ACTIVE(640),
        .H_BEATS(160)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tuser(s_axis_tuser),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser)
    );

    // ==========================================================
    // 输入图像 ROM  (76800 = 480行 x 160拍/行)
    // ==========================================================
    reg [31:0] img_rom [0:76799];
    integer    beat_cnt;             // 已发送的拍数  0..76799
    integer    gap_cnt;              // 行间隙计数器

    reg [7:0]  beat_in_row;          // 0..159, 行内第几拍
    reg [8:0]  row_cnt;              // 0..479, 第几行

    // ==========================================================
    // 文件输出
    // ==========================================================
    integer    f_ctrl;
    integer    f_pix;
    integer    f_ctrl_in;
    integer    f_hr;

    initial begin
        $readmemh("E:/vivado project/pcam-udp/input.hex", img_rom);
        f_ctrl    = $fopen("E:/vivado project/pcam-udp/ctrl_out.txt", "w");
        f_pix     = $fopen("E:/vivado project/pcam-udp/pix_out.txt", "w");
        f_ctrl_in = $fopen("E:/vivado project/pcam-udp/ctrl_in.txt", "w");
        f_hr      = $fopen("E:/vivado project/pcam-udp/hr_frame.txt", "w");
        $fwrite(f_hr, "# hr_frame.txt\n");
        $fwrite(f_hr, "# Format: [time] row1_v row2_v beat row tvalid\n");
        $fwrite(f_hr, "#   hr: byte order [31:24] [23:16] [15:8] [7:0], index order [2]|[1]|[0]\n");
    end

    // ==========================================================
    // 复位序列 (用 NBA 避免与 negedge 竞态)
    // ==========================================================
    initial begin
        rst_n <= 1'd0;
        #200;
        rst_n <= 1'd1;
    end

    // ==========================================================
    // S_AXIS 驱动: 模拟 VDMA 行流 (negedge)
    //   每行 160 拍, 行间 3 拍间隙
    //   tlast 在每行末拍, tuser 仅首拍
    // ==========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axis_tvalid  <= 1'd0;
            s_axis_tlast   <= 1'd0;
            s_axis_tuser   <= 1'd0;
            s_axis_tdata   <= 32'd0;
            beat_in_row    <= 8'd0;
            row_cnt        <= 9'd0;
            beat_cnt       <= 0;
            gap_cnt        <= 0;
        end
        else begin
            if (beat_cnt < 76800) begin
                if (beat_in_row == 8'd0 && row_cnt > 9'd0 && gap_cnt < 4) begin
                    // 行间隙: 每行结束后 3 拍无效
                    s_axis_tvalid <= 1'd0;
                    s_axis_tlast  <= 1'd0;
                    s_axis_tuser  <= 1'd0;
                    s_axis_tdata  <= 32'd0;
                    gap_cnt       <= gap_cnt + 1;
                end
                else begin
                    // 有效拍
                    s_axis_tvalid <= 1'd1;
                    s_axis_tdata  <= img_rom[beat_cnt];
                    s_axis_tuser  <= (beat_cnt == 0);
                    s_axis_tlast  <= (beat_in_row == 8'd159);
                    gap_cnt       <= 0;

                    if (beat_in_row == 8'd159) begin
                        beat_in_row <= 8'd0;
                        row_cnt     <= row_cnt + 9'd1;
                    end
                    else begin
                        beat_in_row <= beat_in_row + 8'd1;
                    end
                    beat_cnt <= beat_cnt + 1;
                end
            end
            else begin
                // 全部拍发送完毕
                s_axis_tvalid <= 1'd0;
                s_axis_tlast  <= 1'd0;
                s_axis_tuser  <= 1'd0;
                s_axis_tdata  <= 32'd0;
                gap_cnt       <= gap_cnt + 1;
            end
        end
    end

    // ==========================================================
    // 日志: 
    // ==========================================================
    always @(negedge clk) begin
        if (rst_n) begin
            // ctrl_out.txt: <time> <tvalid> <tlast> <tuser>
            $fwrite(f_ctrl, "%0d %0d %0d %0d\n",
                    $time-210,
                    m_axis_tvalid,
                    m_axis_tlast,
                    m_axis_tuser,
                    );

            // pix_out.txt: <time> <pix3> <pix2> <pix1> <pix0>
            $fwrite(f_pix, "%0d %0d %0d %0d %0d\n",
                    $time-210,
                    m_axis_tdata[31:24],
                    m_axis_tdata[23:16],
                    m_axis_tdata[15:8],
                    m_axis_tdata[7:0],
                    );
                    
            // ctrl_in.txt: <time> <s_tvalid> <s_tlast> <s_tuser> <curr_beat> <curr_row>
            $fwrite(f_ctrl_in, "%0d %0d %0d %0d %0d %0d\n",
                    $time-210,
                    s_axis_tvalid,
                    s_axis_tlast,
                    s_axis_tuser,
                    uut.curr_beat,
                    uut.curr_row);

            // hr_frame.txt
            $fwrite(f_hr, "[%0d] row1_v=%0d row2_v=%0d beat=%0d row=%0d s_tvalid=%0d m_tvalid=%0d\n",
                    $time-210,
                    uut.row1_valid, uut.row2_valid,
                    uut.curr_beat, uut.curr_row,
                    s_axis_tvalid,
                    uut.m_axis_tvalid);

            $fwrite(f_hr, "  hr_row2: %3d %3d %3d %3d  | %3d %3d %3d %3d  | %3d %3d %3d %3d\n",
                    uut.hr_row2[2][31:24], uut.hr_row2[2][23:16], uut.hr_row2[2][15:8], uut.hr_row2[2][7:0],
                    uut.hr_row2[1][31:24], uut.hr_row2[1][23:16], uut.hr_row2[1][15:8], uut.hr_row2[1][7:0],
                    uut.hr_row2[0][31:24], uut.hr_row2[0][23:16], uut.hr_row2[0][15:8], uut.hr_row2[0][7:0]);

            $fwrite(f_hr, "  hr_row1: %3d %3d %3d %3d  | %3d %3d %3d %3d  | %3d %3d %3d %3d\n",
                    uut.hr_row1[2][31:24], uut.hr_row1[2][23:16], uut.hr_row1[2][15:8], uut.hr_row1[2][7:0],
                    uut.hr_row1[1][31:24], uut.hr_row1[1][23:16], uut.hr_row1[1][15:8], uut.hr_row1[1][7:0],
                    uut.hr_row1[0][31:24], uut.hr_row1[0][23:16], uut.hr_row1[0][15:8], uut.hr_row1[0][7:0]);

            $fwrite(f_hr, "  hr_curr: %3d %3d %3d %3d  | %3d %3d %3d %3d  | %3d %3d %3d %3d\n",
                    uut.hr_curr[2][31:24], uut.hr_curr[2][23:16], uut.hr_curr[2][15:8], uut.hr_curr[2][7:0],
                    uut.hr_curr[1][31:24], uut.hr_curr[1][23:16], uut.hr_curr[1][15:8], uut.hr_curr[1][7:0],
                    uut.hr_curr[0][31:24], uut.hr_curr[0][23:16], uut.hr_curr[0][15:8], uut.hr_curr[0][7:0]);

        end
    end


    // ==========================================================
    // 仿真结束: 所有拍发出 + 管线排空 400 拍 (negedge)
    // ==========================================================
    always @(posedge clk) begin
        if (gap_cnt == 400) begin
            $fclose(f_ctrl);
            $fclose(f_pix);
            $fclose(f_ctrl_in);
            $fclose(f_hr);
            $display("=== Simulation finished ===");
            $finish;
        end
    end

endmodule
