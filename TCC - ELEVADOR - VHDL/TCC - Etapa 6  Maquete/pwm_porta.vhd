library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pwm_porta is
    port (
        clk           : in std_logic; -- Ritmo de 50 MHz da placa
        comando_abrir : in std_logic; -- '1' manda o servo abrir, '0' manda fechar
        servo_pwm     : out std_logic -- Sinal elétrico de saída para o pino do Servomotor
    );
end entity;

architecture rtl of pwm_porta is
    -- Constantes matemáticas para o Servomotor baseadas no relógio de 50MHz
    constant PERIODO_TOTAL   : integer := 1_000_000; -- Ciclo de 20ms padrão para servos
    constant PULSO_ABERTO    : integer := 51389;     -- Pulso para posição de 5 graus
    constant PULSO_FECHADO   : integer := 98611;     -- Pulso para posição de 175 graus

    signal contador     : integer range 0 to PERIODO_TOTAL := 0;
    signal largura_alvo : integer range 50000 to 100000 := PULSO_FECHADO;
begin

    -- Processo 1: Define qual deve ser a largura do pulso dependendo da ordem recebida do cérebro.
    process(clk)
    begin
        if rising_edge(clk) then
            if comando_abrir = '1' then
                largura_alvo <= PULSO_ABERTO;
            else
                largura_alvo <= PULSO_FECHADO;
            end if;
        end if;
    end process;

    -- Processo 2: Gera fisicamente a onda elétrica (PWM) ligando e desligando o pino em alta velocidade.
    process(clk)
    begin
        if rising_edge(clk) then
            if contador < PERIODO_TOTAL then
                contador <= contador + 1;
            else
                contador <= 0;
            end if;

            if contador < largura_alvo then
                servo_pwm <= '1';
            else
                servo_pwm <= '0';
            end if;
        end if;
    end process;

end architecture;