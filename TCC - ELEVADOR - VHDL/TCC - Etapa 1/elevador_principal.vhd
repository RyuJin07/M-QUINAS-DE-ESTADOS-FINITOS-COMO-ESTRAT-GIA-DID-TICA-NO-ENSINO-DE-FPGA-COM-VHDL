library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pacote_elevador.all;

entity elevador_principal is
    port (
        -- Batimento do sistema (PIN_P11). Sincroniza todas as ações da placa.
        CLOCK_50 : in std_logic;
        
        -- Botões de pressão. 
        -- KEY[0] é o Reset: limpa a memória e volta ao térreo (PIN_B8).
        KEY      : in std_logic_vector(0 downto 0);
        
        -- SW apagado por completo. O elevador autônomo ignora botões externos.
        
        -- Luzes indicadoras (Monitoramento em tempo real)
        LEDR     : out std_logic_vector(5 downto 4); -- Mantemos apenas as luzes do motor!
        
        -- Visor 0: Indica o número do andar atual (PIN_C14 até PIN_C17).
        HEX0     : out std_logic_vector(6 downto 0);
        
        -- Visor 3: Indica a direção (Seta de subida ou descida) (PIN_F21 até PIN_E17).
        HEX3     : out std_logic_vector(6 downto 0)  
    );
end entity;

architecture rtl of elevador_principal is
    -- Sinais internos para ligar os diferentes blocos do projeto.
    signal rst_n : std_logic;
    
    -- Estados da máquina que controla o comportamento global do elevador.
    -- Como é o Esqueleto Visual, ele apenas oscila entre ESPERA e MOVIMENTO.
    type estado_principal_t is (ESPERA, MOVIMENTO);
    signal estado : estado_principal_t := ESPERA;
    
    signal andar_atual : andar_t := (others=> '0');
    signal direcao : direcao_t := DIR_SOBE; 
    
    -- Cronômetros para o tempo de movimento (2s) e tempo de espera nos andares (1s).
    constant PULSOS_MOVIMENTO : natural := 50_000_000 * 2;
    constant PULSOS_ESPERA    : natural := 50_000_000 * 1;
    signal contagem_tempo : unsigned(31 downto 0) := (others=> '0');

begin
    -- Ligação física dos pinos da placa às variáveis lógicas do sistema.
    rst_n <= KEY(0);
    
    -- Lógica direta e limpa. Nada foi adicionado, apenas mantivemos o controle do motor.
    -- Acende as luzes correspondentes ao movimento do motor.
    LEDR(5 downto 4) <= "01" when direcao=DIR_SOBE else "10" when direcao=DIR_DESCE else "00";
    
    -- Envio dos dados para os conversores de imagem dos visores.
    HEX0 <= decodifica_7seg(resize(andar_atual, 4));
    HEX3 <= hex_dir(direcao);

    -- Processo de Decisão: coordena as ações a cada batida do ritmo (Clock).
    process (CLOCK_50)
        variable a_atual : natural;
    begin
        if rising_edge(CLOCK_50) then
            
            -- Lógica de Reinício: volta ao estado inicial se o botão for pressionado.
            if rst_n='0' then
                estado <= ESPERA; andar_atual <= (others=> '0'); direcao <= DIR_SOBE; contagem_tempo <= (others=> '0');
            else
                a_atual := to_integer(andar_atual);

                -- Máquina de estados autônoma (Loop infinito de vai-e-vem)
                case estado is
                    when ESPERA =>
                        -- Aguarda 1 segundo em cada andar antes de se mover novamente.
                        if contagem_tempo = to_unsigned(PULSOS_ESPERA, contagem_tempo'length) then
                            contagem_tempo <= (others=> '0');
                            estado <= MOVIMENTO;
                        else
                            contagem_tempo <= contagem_tempo + 1;
                        end if;
                        
                    when MOVIMENTO =>
                        -- Controla o tempo de transição entre andares adjacentes.
                        if contagem_tempo = to_unsigned(PULSOS_MOVIMENTO, contagem_tempo'length) then
                            contagem_tempo <= (others=>'0');
                            
                            -- Lógica Ping-Pong pura: Bate no teto e desce, bate no chão e sobe.
                            if direcao = DIR_SOBE then
                                if a_atual = N_ANDARES - 2 then
                                    andar_atual <= andar_atual + 1; direcao <= DIR_DESCE;
                                else
                                    andar_atual <= andar_atual + 1;
                                end if;
                            else
                                if a_atual = 1 then
                                    andar_atual <= andar_atual - 1; direcao <= DIR_SOBE;
                                else
                                    andar_atual <= andar_atual - 1;
                                end if;
                            end if;
                            
                            estado <= ESPERA;
                        else 
                            contagem_tempo <= contagem_tempo + 1; 
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;