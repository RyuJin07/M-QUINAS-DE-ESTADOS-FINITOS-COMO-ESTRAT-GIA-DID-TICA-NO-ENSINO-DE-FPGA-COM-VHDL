library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pacote_elevador.all; 

entity fsm_porta is
    -- O ritmo de funcionamento é ditado pela placa 50 milhões de vezes por segundo. 
    -- Para atingir o tempo de 2 segundos de espera, a contagem interna deve chegar a 100 milhões de batidas.
    generic (
        TEMPO_ABRINDO  : natural := 50_000_000 * 2;
        TEMPO_ABERTA   : natural := 50_000_000 * 5;
        TEMPO_FECHANDO : natural := 50_000_000 * 2 
    );
    port (
        clk             : in std_logic;        -- Sinal de ritmo que sincroniza cada passo do sistema
        rst_n           : in std_logic;        -- Comando que limpa a memória e volta tudo ao estado inicial de segurança
        chegada         : in std_logic;        -- Aviso para iniciar a abertura da porta
        porta_aberta    : out std_logic;       -- Luz que indica que a porta terminou de abrir
        porta_movimento : out std_logic;       -- Luz que indica que o motor da porta está girando
        status_porta    : out status_porta_t;  -- Envia a letra correspondente ao que a porta faz para o visor
        ciclo_concluido : out std_logic        -- Informa ao controle principal que a porta já fechou
    );
end entity;

architecture rtl of fsm_porta is
    type estado_t is (FECHADA, ABRINDO, ABERTA, FECHANDO); 
    signal estado : estado_t := FECHADA;
    
    -- Espaço de memória para o cronômetro. 
    -- Utiliza 32 bits para conseguir registrar as milhões de batidas necessárias para contar os segundos.
    signal contagem : unsigned(31 downto 0) := (others => '0');
begin
    process (clk)
    begin
        if rising_edge(clk) then
            ciclo_concluido <= '0';
            
            if rst_n = '0' then
                estado <= FECHADA; contagem <= (others => '0');
                porta_aberta <= '0'; porta_movimento <= '0'; status_porta <= ST_FECHADA;
            else
                -- Sequência de passos que a porta realiza:
                case estado is
                    when FECHADA =>
                        status_porta <= ST_FECHADA; porta_movimento <= '0'; porta_aberta <= '0';
                        if chegada = '1' then estado <= ABRINDO; contagem <= (others => '0'); end if;
                        
                    when ABRINDO =>
                        status_porta <= ST_ABRINDO; porta_movimento <= '1';
                        -- O sistema segue contando as batidas até completar os 2 segundos de movimento.
                        if contagem = to_unsigned(TEMPO_ABRINDO, contagem'length) then
                            estado <= ABERTA; contagem <= (others => '0');
                        else 
                            contagem <= contagem + 1; 
                        end if;
                        
                    when ABERTA =>
                        status_porta <= ST_ABERTA; porta_aberta <= '1'; porta_movimento <= '0';
                        -- Segue a contagem até atingir o intervalo de 5 segundos com a porta aberta.
                        if contagem = to_unsigned(TEMPO_ABERTA, contagem'length) then
                            estado <= FECHANDO; contagem <= (others => '0');
                        else 
                            contagem <= contagem + 1; 
                        end if;
                        
                    when FECHANDO =>
                        status_porta <= ST_FECHANDO; porta_aberta <= '0'; porta_movimento <= '1';
                        if contagem = to_unsigned(TEMPO_FECHANDO, contagem'length) then
                            estado <= FECHADA; ciclo_concluido <= '1';
                        else 
                            contagem <= contagem + 1; 
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;