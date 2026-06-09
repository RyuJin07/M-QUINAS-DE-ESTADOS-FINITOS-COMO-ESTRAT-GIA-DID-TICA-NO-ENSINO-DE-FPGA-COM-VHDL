library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package pacote_elevador is
    -- Define a quantidade total de andares.  
    -- Assim facilita mudar o tamanho do prédio sem precisar mexer em várias partes do código.
    constant N_ANDARES : natural := 4;
    
    -- Define um tamanho exato para a numeração do andar. Isso economiza 
    -- espaço dentro do chip ao usar apenas 2 fios (bits) para contar de 0 a 3.
     -- Número de fios precisa ser aumentado conforme os andares 3 fios para 4 a 7 por exemplo
    subtype andar_t is unsigned(1 downto 0);
    
    -- Lista os únicos estados permitidos para o motor e para a porta. 
    -- Isso evita que o sistema tente realizar movimentos inválidos.
    type direcao_t is (DIR_PARADA, DIR_SOBE, DIR_DESCE);
    type status_porta_t is (ST_FECHADA, ST_ABRINDO, ST_ABERTA, ST_FECHANDO);

    -- Declaração das funções que traduzem a lógica interna para as luzes que aparecem nos visores da placa.   
    function decodifica_7seg(d : unsigned(3 downto 0)) return std_logic_vector;
    function hex_dir(dir : direcao_t) return std_logic_vector;
    function hex_porta(st : status_porta_t) return std_logic_vector;
end package;

package body pacote_elevador is

    -- Converte o número do andar nos sinais elétricos para o visor de 7 segmentos.
    -- Na placa DE10-Lite, o nível '0' acende o traço e o nível '1' apaga.
    function decodifica_7seg(d : unsigned(3 downto 0)) return std_logic_vector is
        variable seg : std_logic_vector(6 downto 0);
    begin
        case to_integer(d) is
            when 0 => seg := "1000000"; -- Desenha o número '0' no visor
            when 1 => seg := "1111001"; -- Desenha o número '1' no visor
            when 2 => seg := "0100100"; -- Desenha o número '2' no visor
            when 3 => seg := "0110000"; -- Desenha o número '3' no visor
            -- 4 à 9 já feitos para eventuais expansões
            when 4 => seg := "0011001"; -- Desenha o número '4' no visor 
            when 5 => seg := "0010010"; -- Desenha o número '5' no visor
            when 6 => seg := "0000010"; -- Desenha o número '6' no visor
            when 7 => seg := "1111000"; -- Desenha o número '7' no visor
            when 8 => seg := "0000000"; -- Desenha o número '8' no visor
            when 9 => seg := "0010000"; -- Desenha o número '9' no visor
            when 14 => seg := "0000110"; -- Desenha a letra 'E' (Emergência)
            when others => seg := "0001100"; -- Desenha a letra 'P' (Problema) em caso de erro
        end case;
        return seg;
    end function;

    -- Converte a direção do elevador em traços horizontais no visor.
    function hex_dir(dir : direcao_t) return std_logic_vector is
    begin
        case dir is
            when DIR_SOBE => return "1111110";  -- Acende apenas o traço superior, indicando subida
            when DIR_DESCE => return "1110111"; -- Acende apenas o traço inferior, indicando descida
            when DIR_PARADA => return "0111111";-- Acende apenas o traço central, indicando parado
        end case;
    end function;

    -- Converte o estado da porta em letras de fácil identificação.
    function hex_porta(st : status_porta_t) return std_logic_vector is
    begin
        case st is
            when ST_FECHADA => return "1111111"; -- Deixa o visor totalmente apagado
            when ST_ABRINDO | ST_ABERTA => return "0001000"; -- Desenha a letra 'A' (Aberta ou Abrindo)
            when ST_FECHANDO => return "0001110"; -- Desenha a letra 'F' (Fechando)
        end case;
    end function;

end package body;