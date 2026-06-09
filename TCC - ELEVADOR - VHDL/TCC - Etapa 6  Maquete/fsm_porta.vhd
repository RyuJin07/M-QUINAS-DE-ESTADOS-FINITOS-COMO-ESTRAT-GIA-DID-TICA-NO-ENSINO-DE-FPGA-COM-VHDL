library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pacote_elevador.all; 

entity fsm_porta is
    generic (
        TEMPO_ABERTA : natural := 50_000_000 * 5 
    );
    port (
        clk               : in std_logic;        -- Sinal de ritmo que sincroniza cada passo do sistema
        rst_n             : in std_logic;        -- Comando que limpa a memória e volta ao estado de segurança
        chegada           : in std_logic;        -- Aviso para iniciar a abertura da porta
        excesso_peso      : in std_logic;        -- Sensor que indica se o limite de peso foi atingido
        sensor_barreira   : in std_logic;        -- Sensor que detecta se há algo bloqueando a porta
		  
        -- Entradas dos sensores (chaves fim de curso)
        sensor_fim_aberta  : in std_logic;       -- Confirma fisicamente que a porta abriu tudo
        sensor_fim_fechada : in std_logic;       -- Confirma fisicamente que a porta fechou tudo 
		  
        -- Saída que envia a ordem para o módulo PWM girar o servo
        comando_servo     : out std_logic;       
        porta_aberta      : out std_logic;       -- Luz que indica que a porta terminou de abrir
        porta_movimento   : out std_logic;       -- Luz que indica que o motor da porta está em ação
        status_porta      : out status_porta_t;  -- Envia a letra correspondente para o visor
        ciclo_concluido   : out std_logic        -- Informa ao controle principal que a porta já fechou
    );
end entity;

architecture rtl of fsm_porta is
    type estado_t is (FECHADA, ABRINDO, ABERTA, FECHANDO); 
    signal estado : estado_t := FECHADA;
    
    -- Espaço de memória para o cronómetro de embarque (5 segundos).
    signal contagem : unsigned(31 downto 0) := (others => '0');
    signal concluido_s : std_logic := '0';
begin
    ciclo_concluido <= concluido_s;

    process (clk)
    begin
        if rising_edge(clk) then
            concluido_s <= '0'; 
            
            if rst_n = '0' then
                estado <= FECHADA;
                contagem <= (others => '0');
                porta_aberta <= '0'; porta_movimento <= '0';
                status_porta <= ST_FECHADA;
                comando_servo <= '0'; -- Mantém o servo na posição fechada por segurança
            else
                case estado is
                    when FECHADA =>
                        porta_aberta <= '0'; porta_movimento <= '0'; status_porta <= ST_FECHADA;
                        comando_servo <= '0';
                        contagem <= (others => '0');
                        if chegada = '1' then estado <= ABRINDO; end if;
                        
                    when ABRINDO =>
                        porta_aberta <= '0'; porta_movimento <= '1'; status_porta <= ST_ABRINDO;
                        comando_servo <= '1'; -- Envia a ordem para o servo puxar a porta             
                        if sensor_fim_aberta = '1' then -- Confirma porta aberta
                            estado <= ABERTA; contagem <= (others => '0');
                        end if;
                        
                    when ABERTA => 
                        porta_aberta <= '1'; porta_movimento <= '0'; status_porta <= ST_ABERTA;
                        comando_servo <= '1';
                        
                        -- Regra de segurança: Se houver excesso de peso ou obstrução, o cronómetro é zerado.
                        if excesso_peso = '1' or sensor_barreira = '1' then
                            contagem <= (others => '0'); 
                        else
                            -- Conta os pulsos do relógio até atingir os 5 segundos reais para embarque.
                            if contagem = to_unsigned(TEMPO_ABERTA, contagem'length) then
                                estado <= FECHANDO; contagem <= (others => '0');
                            else
                                contagem <= contagem + 1;
                            end if;
                        end if;
                        
                    when FECHANDO =>
                        porta_aberta <= '0'; porta_movimento <= '1'; status_porta <= ST_FECHANDO;
                        comando_servo <= '0'; -- Envia a ordem para o servo empurrar a porta
                        
                        -- Sensor de proteção: Se algo interromper o fechamento, volta a abrir na hora.
                        if sensor_barreira = '1' then
                            estado <= ABERTA; contagem <= (others => '0'); 
                        else
                            if sensor_fim_fechada = '1' then -- Confirma porta fechada
                                estado <= FECHADA; concluido_s <= '1'; contagem <= (others => '0');
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;