`define STAGE_IDLE        0
`define STAGE_KEY_OP      1
`define STAGE_LINE_OP     2 
`define STAGE_NONLINE_OP  3
`define STAGE_FINAL       4

module cipher(
    input               clk_i,      // Тактовый сигнал
                        resetn_i,   // Синхронный сигнал сброса с активным уровнем LOW
                        request_i,  // Сигнал запроса на начало шифрования
                        ack_i,      // Сигнал подтверждения приема зашифрованных данных
                [127:0] data_i,     // Шифруемые данные

    output          reg busy_o,     // Сигнал, сообщающий о невозможности приёма
                                    // очередного запроса на шифрование, поскольку
                                    // модуль в процессе шифрования предыдущего
                                    // запроса
           reg          valid_o,    // Сигнал готовности зашифрованных данных
           reg  [127:0] data_o      // Зашифрованные данные
);

/* ------------------- Табличные значения --------------------- */
reg [127:0] key_mem [0:9];
reg [7:0] S_box_mem [0:255];
reg [7:0] L_mul_16_mem  [0:255];
reg [7:0] L_mul_32_mem  [0:255];
reg [7:0] L_mul_133_mem [0:255];
reg [7:0] L_mul_148_mem [0:255];
reg [7:0] L_mul_192_mem [0:255];
reg [7:0] L_mul_194_mem [0:255];
reg [7:0] L_mul_251_mem [0:255];
/* ------------------- Табличные значения --------------------- */

initial begin
    $readmemh("keys.mem",key_mem );
    $readmemh("S_box.mem",S_box_mem );

    $readmemh("L_16.mem", L_mul_16_mem );
    $readmemh("L_32.mem", L_mul_32_mem );
    $readmemh("L_133.mem",L_mul_133_mem);
    $readmemh("L_148.mem",L_mul_148_mem);
    $readmemh("L_192.mem",L_mul_192_mem);
    $readmemh("L_194.mem",L_mul_194_mem);
    $readmemh("L_251.mem",L_mul_251_mem);
end

logic [127:0] current_data; // Данные на текущем этапе машины состояния
logic [3:0] mState;         // Состояние конечного автомата
logic [3:0] trial_num_ff;   // Счетчик стадий шифрования

// Наложение ключа
logic [127:0] key_overlay_result;
key_overlay_module key_overlay(
  .round_key(key_mem[trial_num_ff]),
  .trial_input_mux(current_data),
  .data_key_result(key_overlay_result)
);

// Линейные преобразования
logic [7:0] linear_overlay_result [15:0];
linear_overlay_module linear_overlay(
  .S_box_mem(S_box_mem),
  .input_data(current_data),
  .data_linear_result(linear_overlay_result)
);

// Нелинейные преобразования
logic nonlinear_request;                    // Запрос на нелинейное преобразование
logic result_formed;                        // Сигнал о том что результат сформирован
logic [7:0]   nonlinear_overlay_i [15:0];   // Входные данные для нелинейного преобразования
logic [127:0] nonlinear_overlay_result;     // Результат нелинейного преобразования
nonlinear_overlay_module nonlinear_overlay(
  .clk_i(clk_i),
  .resetn_i(resetn_i),
  .data_linear_result(nonlinear_overlay_i),
  .L_mul_16_mem(L_mul_16_mem),
  .L_mul_32_mem(L_mul_32_mem),
  .L_mul_133_mem(L_mul_133_mem),
  .L_mul_148_mem(L_mul_148_mem),
  .L_mul_192_mem(L_mul_192_mem),
  .L_mul_194_mem(L_mul_194_mem),
  .L_mul_251_mem(L_mul_251_mem),
  .data_nonlinear_result(nonlinear_overlay_result),
  .result_formed(result_formed),
  .request_i(nonlinear_request)
);

always_ff @(posedge clk_i or negedge resetn_i) begin
  if (~resetn_i)
  begin
    mState = `STAGE_IDLE;
    busy_o = 0;
    valid_o = 0;
    data_o = 0;
    current_data = 0;
    trial_num_ff = 0;
    nonlinear_request = 0;
  end
  else
  begin
    if(valid_o) // Данные сформированы
    begin
      if(ack_i) // Данные дошли до получателя
        valid_o <= 0;
    end
    else
    begin
      if(request_i && (mState == `STAGE_IDLE || mState == `STAGE_FINAL)) begin
        // Начинаем цикл обработки информации
        mState <= `STAGE_KEY_OP; // Переходим в стадию покрытия данных ключом
        busy_o <= 1;
        current_data = data_i;
      end
    end

    case(mState)
      `STAGE_KEY_OP: begin
        // Получаем покрытые ключом данные и переходим
        // на стадию линейного преобразования
        if(trial_num_ff >= 9) 
        begin
          // Пройдена 10 стадия шифрования
          mState <= `STAGE_FINAL;
          current_data = key_overlay_result;
          busy_o <= 0;
          valid_o <= 1;
          data_o <= current_data;
        end
        else
        begin
          // Переход к линейным преобразованиям
          mState <= `STAGE_LINE_OP;
          current_data = key_overlay_result;
        end
      end
      `STAGE_LINE_OP: begin
        // Получаем линейно преобразованные данные и переходим
        // на стадию нелинейного преобразования
        nonlinear_overlay_i = linear_overlay_result;
        mState <= `STAGE_NONLINE_OP;
        nonlinear_request = '1;
      end
      `STAGE_NONLINE_OP: begin
        // Ожидаем нелинейно преобразованные данные
        // и переходим на стадию наложения ключа
        nonlinear_request = '0;
        if(result_formed == 1)
        begin
          current_data = nonlinear_overlay_result;
          mState <= `STAGE_KEY_OP;
          // Добавляем значение к количеству произведенных циклов операций над данныим
          trial_num_ff += 1;
        end
      end
      `STAGE_FINAL: begin
        trial_num_ff = 0;
        if(request_i)
          mState <= `STAGE_KEY_OP; // Переходим в стадию покрытия данных ключом
        else
          mState <= `STAGE_IDLE; // Переходим в стадию ожиданий
      end
    endcase
  end
end

endmodule
/* ------------------ KEY OVERLAY --------------------- */
module key_overlay_module(
  input
  [127:0] round_key,
  [127:0] trial_input_mux,
  output
  [127:0] data_key_result
);
  // Наложение ключа
  assign data_key_result = trial_input_mux ^ round_key;
endmodule
/* ------------------ KEY OVERLAY --------------------- */

/* ------------------ LINEAR OVERLAY --------------------- */
module linear_overlay_module(
  input
  [7:0] S_box_mem [0:255],
  [127:0] input_data,
  output
  [7:0] data_linear_result    [15:0]
);
  // Линейные преобразования
  logic [7:0] data_key_result_bytes [15:0];
  logic [7:0] data_linear_result    [15:0];

  generate;
    for (genvar i=0; i<16; i++) begin
      assign data_key_result_bytes[i] = input_data[((i+1)*8)-1:(i*8)];
      assign data_linear_result   [i] = S_box_mem[data_key_result_bytes[i]]; // Заменяем значение на полученное из таблицы
    end
  endgenerate
endmodule
/* ------------------ LINEAR OVERLAY --------------------- */

/* ------------------ NONLINEAR OVERLAY --------------------- */
module nonlinear_overlay_module(
  input clk_i,
        resetn_i,
        request_i,
  [7:0] data_linear_result [15:0],
  [7:0] L_mul_16_mem  [0:255],
  [7:0] L_mul_32_mem  [0:255],
  [7:0] L_mul_133_mem  [0:255],
  [7:0] L_mul_148_mem  [0:255],
  [7:0] L_mul_192_mem  [0:255],
  [7:0] L_mul_194_mem  [0:255],
  [7:0] L_mul_251_mem  [0:255],
  output logic result_formed,
  [127:0] data_nonlinear_result
);
  logic [127:0] nonlinear_result;     // Результат вычислений
  assign data_nonlinear_result = nonlinear_result;

  logic busy = 0;                     // Флаг занятости модуля
  logic [3:0] operation_counter = 0;  // Счетчик операций
    
  logic [7:0] data_galua_in [15:0];

  logic [7:0] data_galua_result [15:0];

  // Table Ratio  148, 32, 133, 16, 194, 192, 1, 251, 1, 192, 194, 16, 133, 32, 148, 1
  // Number Index  15, 14,  13, 12,  11,  10, 9,   8, 7,   6,   5,  4,   3,  2,   1, 0
  assign data_galua_result[15]  = L_mul_148_mem [data_galua_in[15]];
  assign data_galua_result[14]  = L_mul_32_mem  [data_galua_in[14]]; 
  assign data_galua_result[13]  = L_mul_133_mem [data_galua_in[13]]; 
  assign data_galua_result[12]  = L_mul_16_mem  [data_galua_in[12]]; 
  assign data_galua_result[11]  = L_mul_194_mem [data_galua_in[11]]; 
  assign data_galua_result[10]  = L_mul_192_mem [data_galua_in[10]]; 
  assign data_galua_result[9]   =                data_galua_in[9] ;
  assign data_galua_result[8]   = L_mul_251_mem [data_galua_in[8]]; 
  assign data_galua_result[7]   =                data_galua_in[7] ;
  assign data_galua_result[6]   = L_mul_192_mem [data_galua_in[6]]; 
  assign data_galua_result[5]   = L_mul_194_mem [data_galua_in[5]]; 
  assign data_galua_result[4]   = L_mul_16_mem  [data_galua_in[4]]; 
  assign data_galua_result[3]   = L_mul_133_mem [data_galua_in[3]]; 
  assign data_galua_result[2]   = L_mul_32_mem  [data_galua_in[2]]; 
  assign data_galua_result[1]   = L_mul_148_mem [data_galua_in[1]]; 
  assign data_galua_result[0]   =                data_galua_in[0] ;

  logic [7:0] galua_summ; // Сумма произведений
  logic [127:0] trial_output; // Промежуточный результат

  logic [7:0] data_galua_shreg        [15:0]; // Сдвиговый регистр
  logic [7:0] data_galua_shreg_next   [15:0]; // 

/*-------------------------------- GENERATE LOGIC ----------------------------------*/
generate;
  // Преобразование байтов в строку из массива
  for (genvar i = 0; i < 16; i++)
    assign trial_output[((i+1)*8)-1:(i*8)] = data_galua_shreg_next[i];

  // Вычисляем сумму произведений
  always_comb begin
    galua_summ = '0;
    for (int i = 0; i < 16; i++)
      galua_summ = galua_summ ^ data_galua_result[i];
  end

  // Формирование состояния нового сдвигового регистра
  always_comb begin
    data_galua_shreg_next[15] = galua_summ;
    for (int i = 14; i >= 0; i--)
      data_galua_shreg_next[i] = data_galua_shreg[i+1];
  end

  // Сформированный сдвиговый регистр дублиру
  for (genvar i = 0; i < 16; i++) begin
    always_ff @(posedge clk_i or negedge resetn_i) begin
      if (~resetn_i)
        data_galua_shreg[i] = '0;
      else if (busy)
        data_galua_shreg[i] = data_galua_shreg_next[i];
    end
  end
endgenerate
/*-------------------------------- GENERATE LOGIC ----------------------------------*/

assign data_galua_in = request_i ? data_linear_result : data_galua_shreg;

always_comb begin
  
  if(request_i && !busy)
  begin
    // Запуск новых значений на нелинейные преобразования
    busy = 1;
    operation_counter = 0;
    result_formed = 0;
    data_galua_shreg = data_galua_in;
  end
end

always_ff @(posedge clk_i or negedge resetn_i)
begin
  if(~resetn_i)
    begin
      operation_counter = 0;
      busy = 0;
      result_formed = 0;
    end
  else
    begin
      if(request_i && !busy)
      begin
        // Запуск новых значений на нелинейные преобразования
        //data_galua_in = data_linear_result;
      end
      
      if(busy)
        begin

          if(operation_counter == 15)
          begin
            nonlinear_result <= trial_output;
            result_formed <= 1;
            busy <= 0;
            operation_counter <= 0;
          end
          else
            operation_counter <= operation_counter + 1; // счетчик операций (16)
        end
    end
end
endmodule
/* ------------------ NONLINEAR OVERLAY --------------------- */