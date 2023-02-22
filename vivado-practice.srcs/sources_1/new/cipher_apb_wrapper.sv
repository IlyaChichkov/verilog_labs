module kuznechik_cipher_apb_wrapper(

    // Clock
    input  logic            pclk_i,

    // Reset
    input  logic            presetn_i,

    // Address
    input  logic     [31:0] paddr_i,
    /*  Шина адреса выровненная до 4х байт. Чтобы
        работать с отдельными байтами из диапазона
        0x00-0x03 используется PSTRB
    */

    // Control-status
    input  logic            psel_i,
    /*  Сигнал выбора данного устройства. Пока он
        равен нулю, остальные (кроме clk и rst)
        игнорируются. На следующий такт, после
        поднятия PSEL, поднимается PENABLE.
    */
    input  logic            penable_i,
    /*  Сигнал, указывающий на вторую и
        последующие такты передачи. Если PREADY
        сделать регистром, и поднимать его по PSEL,
        то PREADY будет подниматься одновременно с
        PENABLE, отражая рукопожатие.
    */
    input  logic            pwrite_i,
    /*  Этот сигнал определяет возможность 
        записи в APB когда сигнал 1
        и доступ к чтению когда сигнал 0
    */

    // Write
    input  logic [3:0][7:0] pwdata_i,
    /*  Эта шина используется при циклах записи
        когда pwrite_i на высоком уровне, максимум
        32бита
    */
    input  logic      [3:0] pstrb_i,
    /*  Сигнал выбора отдельного байта из шины
        данных. Можно подвести отдельные байты
        шины данных к регистрам из диапазона 0x00-
        0x03 и записывать в них по разрешающему
        сигналу с соответствующего бита PSTR
    */


    // Slave
    output logic            pready_o,
    /*  Slave использует данный сигнал для использования передачи по APB
    */
    output logic     [31:0] prdata_o,
    /*  Выбранный slave использует эту шину при
        циклах чтения, когда pwrite - 0. Шина
        имеет максимальный размер в 32 бита
    */
    output logic            pslverr_o
    /*  Сигнал определяет ошибку в передаче. Переферия
        APB не обязана поддерживать этот сигнал. Когда на устройтстве
        нет соответствующего сигнала, на мосте APB должен быть выставлен
        входной сигнал в 0
    */

);

    localparam IDLE = 2'b00;
    localparam BUSY = 2'b01;
    localparam READ = 2'b10;

    ////////////////////
    // Design package //
    ////////////////////

    import kuznechik_cipher_apb_wrapper_pkg::*;


    //////////////////////////
    // Cipher instantiation //
    //////////////////////////
    logic resetn;
    logic [2:0] state;

    // Instantiation
    cipher cipher(
        .clk_i      (  clk      ),
        .resetn_i   (  resetn   ),
        .request_i  (  request  ),
        .ack_i      (  ack      ),
        .data_i     (  data_i   ),
        .busy_o     (  busy     ),
        .valid_o    (  valid    ),
        .data_o     (  data_o   )
    );

    assign resetn = !(presetn_i && RST);

    always_ff @( posedge pclk_i or negedge presetn_i ) begin
        if(~presetn_i)
        begin
            
        end
        else
        begin
            case(state)
            IDLE:
                begin
                    // новые данные -> STATE = BUSY

                    // запрос на чтение -> STATE = READ

                end
            BUSY:
                begin
                    // вычисления
                end
            READ:
                begin
                    // 
                end
            endcase
        end
    end

    /*
        Запись без ожидания:
        paddr
        pwrite = 1
        psel
        pwdata

        2 такт
        penable
        pready = 1

        Запись с ожиданием:
        paddr
        pwrite = 1
        psel
        pwdata

        2 такт
        penable
        >> pready устанавливается только после полной передачи данных

        Чтение без ожидания
        paddr
        pwrite = 0
        при penable выставляется prdata; pready = 1
        . Если периферийное устройство хочет задержать цикл чтения, оно должно снять
        сигнал PREADY при высоком уровне сигнала PENABLE. Тогда ведущее устройство перейдет в
        состояние ожидания до тех пор, пока не получит активного уровня сигнала PREADY.


        Чтение с ожиданием


    */

endmodule