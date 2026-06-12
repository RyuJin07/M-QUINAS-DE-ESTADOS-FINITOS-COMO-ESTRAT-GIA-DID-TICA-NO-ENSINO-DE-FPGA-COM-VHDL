library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pacote_elevador.all;

entity fsm_porta is
    generic (
        TEMPO_ABRINDO  : natural := 50_000_000 * 2;
        TEMPO_ABERTA   : natural := 50_000_000 * 5;
        TEMPO_FECHANDO : natural := 50_000_000 * 2
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        chegada         : in  std_logic;
        excesso_peso    : in  std_logic;
        sensor_barreira : in  std_logic;
        porta_aberta    : out std_logic;
        porta_movimento : out std_logic;
        status_porta    : out status_porta_t;
        ciclo_concluido : out std_logic
    );
end entity;

architecture rtl of fsm_porta is
    type estado_t is (FECHADA, ABRINDO, ABERTA, FECHANDO);
    signal estado : estado_t := FECHADA;
    signal contagem : unsigned(31 downto 0) := (others => '0');
begin
    process(clk)
    begin
        if rising_edge(clk) then
            ciclo_concluido <= '0';

            if rst_n = '0' then
                estado <= FECHADA;
                contagem <= (others => '0');
                porta_aberta <= '0';
                porta_movimento <= '0';
                status_porta <= ST_FECHADA;
            else
                case estado is
                    when FECHADA =>
                        porta_aberta <= '0';
                        porta_movimento <= '0';
                        status_porta <= ST_FECHADA;
                        contagem <= (others => '0');
                        if chegada = '1' then
                            estado <= ABRINDO;
                        end if;

                    when ABRINDO =>
                        porta_aberta <= '0';
                        porta_movimento <= '1';
                        status_porta <= ST_ABRINDO;
                        if contagem >= to_unsigned(TEMPO_ABRINDO-1, contagem'length) then
                            estado <= ABERTA;
                            contagem <= (others => '0');
                        else
                            contagem <= contagem + 1;
                        end if;

                    when ABERTA =>
                        porta_aberta <= '1';
                        porta_movimento <= '0';
                        status_porta <= ST_ABERTA;
                        if excesso_peso = '1' or sensor_barreira = '1' then
                            contagem <= (others => '0');
                        else
                            if contagem >= to_unsigned(TEMPO_ABERTA-1, contagem'length) then
                                estado <= FECHANDO;
                                contagem <= (others => '0');
                            else
                                contagem <= contagem + 1;
                            end if;
                        end if;

                    when FECHANDO =>
                        porta_aberta <= '0';
                        porta_movimento <= '1';
                        status_porta <= ST_FECHANDO;
                        if sensor_barreira = '1' then
                            estado <= ABERTA;
                            contagem <= (others => '0');
                        else
                            if contagem >= to_unsigned(TEMPO_FECHANDO-1, contagem'length) then
                                estado <= FECHADA;
                                contagem <= (others => '0');
                                ciclo_concluido <= '1';
                            else
                                contagem <= contagem + 1;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
