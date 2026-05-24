`timescale 1ns / 1ps

module sobel_core(
    clk,
    rst_n,
    s_axis_tdata,
    s_axis_tvalid,
    s_axis_tready,
    s_axis_tlast,
    s_axis_tuser,
    m_axis_tdata,
    m_axis_tvalid,
    m_axis_tready,
    m_axis_tlast,
    m_axis_tuser
    );
    input clk;
    input rst_n;
    
    input [31:0] s_axis_tdata;
    input s_axis_tvalid;
    output s_axis_tready;
    input s_axis_tlast;
    input s_axis_tuser;
    
    output [31:0] m_axis_tdata;
    output m_axis_tvalid;
    input m_axis_tready;
    output m_axis_tlast;
    output m_axis_tuser;
    
    parameter H_ACTIVE = 640;
    parameter H_BEATS = 160;
    parameter DELAY = 2 % 160;           //从某输入像素块到，其刚好padd到sobel的最底层的延迟。
    
    wire [31:0] row1_beat, row2_beat;
    wire        row1_valid, row2_valid;
    reg         s_tuser_done;
    reg         last_item;
    
    reg [DELAY:0] pipeline_delay;         //最终未使用，全程用curr beat和curr row完成输出控制信号
    
    reg [7:0] curr_beat;    //0~159, 行内第几拍
    reg [8:0] curr_row;     //0~479，第多少行
    
    
    //==================================流水线结构================================================================
    //      s_tdata -> hr_curr[0], [1], [2]
    //          |
    //          |->  lb0[curr], [curr+1], ... , [curr-1]
    //                                              |
    //                                              |-> lb1[curr], [curr+1], ... , [curr-1]
    //                                              |-> hr_row1[0], [1], [2]          |
    //                                                                                |-> hr_row2[0], [1], [2]
    //==========================================================================================================
    //
    // CARE: 若当前【第一次】s_tvalid=0，当前输入无效，不被推入lb，不被推入hr_curr
    //                       当前lb有效，推入hr_row1 row2
    //          假设gap=1，期间s_tvalid=0
    //         at gap: 当前输入无效，不推入lb，不推入hr_curr， pipeline_delay[0] <= 0;
    //                 当前lb有效，推入hr_row1 row2
    //                 当前输出中心pipeline_delay[2]有效。
    //       at gap+1: 当前输入有效，推入lb，推入hr_curr，pipeline_delay[0] <= 1;
    //                 hr_row1, row2仍保持
    //       at gap+2: 正常运转
    
    
    always@(posedge clk) begin
        if (!rst_n) begin
            pipeline_delay <= 3'b0;        //CARE: 这里硬编码了pipeline delay长度
        end
        else begin
            //当前各个pipeline位置是否valid，此处pipeline长度为3
            //                      老                   新                最新
            //                <sobel中心 hr[1]>    <sobel右侧 hr[0]>   <sobel外 lb>
            pipeline_delay <= {pipeline_delay[1], pipeline_delay[0], s_axis_tvalid};
        end
    end
    
    
    always@(posedge clk) begin
        if (!rst_n) begin
            s_tuser_done <= 1'b0;
        end
        else if (s_axis_tuser) begin
            s_tuser_done <= 1'b1;
        end
        else if (last_item) begin
            s_tuser_done <= 1'b0;
        end
    end
    
    //最后一个元素需要推入
    always @(posedge clk) begin
        if (!rst_n) begin
            last_item <= 1'b0;
        end
        else if (curr_row == 9'd480 && curr_beat == 0) begin
            last_item <= 1'b1;
        end
        else if (last_item) begin
            last_item <= 1'b0;
        end
    end
    
    always @(posedge clk) begin
        if (!rst_n) begin
            curr_beat <= 0;
            curr_row <= 0;
        end
        else if (s_axis_tvalid || last_item) begin
            //当前输入块有效，可更新beat和row
            if (s_axis_tuser) begin
                //如果目前是sof，初始化in beat和in row，当前输入可被推入（延迟#1）
                curr_beat <= 1;
                curr_row <= 0;
            end
            else if (s_axis_tlast) begin
                //如果目前是eol，行结束；下一cycle（#1后） inbeat=0，inrow+1
                //当前inbeat=159，收到1帧tlast会让inbeat到0。
                curr_beat <= 0;
                curr_row <= curr_row + 1'd1;
            end
            else begin
                //当前块有效，目前就是块的其中
                curr_beat <= curr_beat + 1'd1;
            end
        end
    end
    
    line_buffer #(.depth(H_BEATS)) lb0(
        .clk(clk), .rst_n(rst_n),
        .data_in(s_axis_tdata), .valid_in((s_axis_tvalid)), //当前s tdata不valid则不推入
        .data_out(row1_beat),   .valid_out(row1_valid)
    );
    line_buffer #(.depth(H_BEATS)) lb1(
        .clk(clk), .rst_n(rst_n),
        .data_in(row1_beat), .valid_in((row1_valid && s_axis_tvalid)),  //当前s tdata不valid则不推入
        .data_out(row2_beat),   .valid_out(row2_valid)
    );
    
    // 当前行：[0]=最新，[1]=1拍前，[2]=2拍前
    reg [31:0] hr_curr [0:2];
    // 上一行
    reg [31:0] hr_row1 [0:2];
    // 上两行
    reg [31:0] hr_row2 [0:2];
    

    
    
    
    always @(posedge clk) begin
        if (!rst_n) begin
            hr_curr[0] <= 0; hr_curr[1] <= 0; hr_curr[2] <= 0;
            hr_row1[0] <= 0; hr_row1[1] <= 0; hr_row1[2] <= 0;
            hr_row2[0] <= 0; hr_row2[1] <= 0; hr_row2[2] <= 0;
        end
        else if (s_axis_tvalid) begin //若当前lb内数据是valid的，推入
            // shift: row1和row2所有窗口移右
            // 若当前lb内数据是valid，当前输入块有效，

            hr_row1[2] <= hr_row1[1];
            hr_row1[1] <= hr_row1[0];
            hr_row1[0] <= row1_beat;
            
            hr_row2[2] <= hr_row2[1];
            hr_row2[1] <= hr_row2[0];
            hr_row2[0] <= row2_beat;
        end
        if (s_axis_tvalid) begin //若当前s_tdata是valid的，才会被推入hr
            //shift hr所有窗口->
            hr_curr[2] <= hr_curr[1];
            hr_curr[1] <= hr_curr[0];
            hr_curr[0] <= s_axis_tdata;
        end
        //else begin
            //【以下都是错的】
            // shift: 只当前row shift一次
            // 当不s_tvalid时，当前输入块无效，第一个row顺移一次，其他不动
            //hr_curr[2] <= hr_curr[1];
            //hr_curr[1] <= hr_curr[0];
            //hr_curr[0] <= s_axis_tdata;
        //end
    end
    
    wire [7:0] mag_vec [0:3];
    
    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin: gen_sobel
            // row2 top of 3x3 window
            wire [7:0] w00 = (gi == 0) ? ((curr_beat == DELAY) ? 8'd0 : hr_row2[2][31:24])
                           : hr_row2[1][(gi-1)*8 +: 8];
            wire [7:0] w01 = hr_row2[1][gi*8 +: 8];
            wire [7:0] w02 = (gi == 3) ? ((curr_beat == (DELAY+159)%160) ? 8'd0 : hr_row2[0][7:0])
                           : hr_row2[1][(gi+1)*8 +: 8];
                           
            // row1 middle of 3x3 window
            wire [7:0] w10 = (gi == 0) ? ((curr_beat == DELAY) ? 8'd0 : hr_row1[2][31:24])
                           : hr_row1[1][(gi-1)*8 +: 8];
            wire [7:0] w11 = hr_row1[1][gi*8+:8];
            wire [7:0] w12 = (gi == 3) ? ((curr_beat == (DELAY+159)%160) ? 8'd0 : hr_row1[0][7:0])
                           : hr_row1[1][(gi+1)*8 +: 8];
            
            // row 0 bottom of 3x3 window, current row
            wire [7:0] w20 = (gi == 0) ? ((curr_beat == DELAY) ? 8'd0 : hr_curr[2][31:24])
                           : hr_curr[1][(gi-1)*8 +: 8];
            wire [7:0] w21 = hr_curr[1][gi*8+:8];
            wire [7:0] w22 = (gi == 3) ? ((curr_beat == (DELAY+159)%160) ? 8'd0 : hr_curr[0][7:0])
                           : hr_curr[1][(gi+1)*8 +: 8];
            
            sobel_kernel sk_inst(
                .p00(w00), .p01(w01), .p02(w02),
                .p10(w10), .p11(w11), .p12(w12),
                .p20(w20), .p21(w21), .p22(w22),
                .mag(mag_vec[gi])
            );
        end
    endgenerate
    
    // =========output: m_tdata, s_tready==================
    reg [31:0] m_axis_tdata_reg;
    always @(posedge clk) begin
        //无论如何都将输出m_tdata设置一下。
        //就算当前输入块无效，那么当前结果就无效，忽略掉即可
        m_axis_tdata_reg <= {mag_vec[3], mag_vec[2], mag_vec[1], mag_vec[0]};
    end
    
    assign m_axis_tdata = m_axis_tdata_reg;
    //向上永远ready
    assign s_axis_tready = 1'b1;
    
    // =========output: m_tvalid, m_tuser, m_tlast==================

    
    
    reg m_tvalid_reg, m_tlast_reg, m_tuser_reg;
    reg m_tuser_done;
    
    //控制往下游发m_tuser
    always @(posedge clk) begin
        if (!rst_n) begin
            m_tuser_reg <= 1'b0;
            m_tuser_done <= 1'b0;
        end
        else begin
            if (s_axis_tuser) begin// 若收到上游s_tuser。则准备给下游发m_tuser
                m_tuser_done <= 1'b0;
            end
            else if ((curr_row == 9'd2) && (curr_beat == DELAY - 1) && !m_tuser_done) begin
                //已经发送m_tuser，需要比delay提前一个cycle
                m_tuser_reg <= 1'b1;
                m_tuser_done <= 1'b1;
            end
            if (m_tuser_done) begin
                m_tuser_reg <= 1'b0;
            end
        end
    end
    
    //控制往下游发tlast
    always @(posedge clk) begin
        if (!rst_n) begin
            m_tlast_reg <= 1'b0;
        end
        else if (curr_row >= 9'd3 && curr_row <= 9'd480 && curr_beat == (DELAY+159)%160) begin
            m_tlast_reg <= 1'b1;
        end

        else if (m_tlast_reg) begin
            m_tlast_reg <= 1'b0;
        end
    end
    
    //控制往下游发tvalid
    always @(posedge clk) begin
        if (!rst_n) begin
            m_tvalid_reg <= 0;
        end
        else if (m_tuser_reg) begin
            m_tvalid_reg <= 1'b1;
        end
        else if (curr_row >= 9'd3 && curr_row <= 9'd479 && s_axis_tvalid) begin
            m_tvalid_reg <= 1'b1;
        end
        else if (last_item) begin
            m_tvalid_reg <= 1;
        end
        else if (!s_axis_tvalid) begin
            m_tvalid_reg <= 1'b0;
        end
        
    end
    
    assign m_axis_tvalid = m_tvalid_reg;
    assign m_axis_tlast  = m_tlast_reg;
    assign m_axis_tuser  = m_tuser_reg;
    
endmodule
