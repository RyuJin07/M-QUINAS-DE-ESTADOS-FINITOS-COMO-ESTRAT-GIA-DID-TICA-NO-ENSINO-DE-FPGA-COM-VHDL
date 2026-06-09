library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pacote_elevador.all;

entity despachante is
    generic (N: natural := 4);
    port (
        andar_atual : in andar_t;
        dir_entrada : in direcao_t;
        pend_int    : in std_logic_vector(N-1 downto 0); -- Lista de botões apertados dentro da cabine
        pend_ext    : in std_logic_vector(N-1 downto 0); -- Lista de botões apertados nos corredores
        tem_destino : out std_logic;                     -- Sinaliza se existe algum andar para visitar
        destino     : out andar_t;                       -- Indica o número do próximo andar escolhido
        dir_saida   : out direcao_t                      -- Indica a direção que o motor deve seguir
    );
end entity;

architecture rtl of despachante is

    -- Verifica se existe qualquer luz de chamada ativa em toda a lista de andares.
    function tem_alguma(p: std_logic_vector) return boolean is
    begin
        for i in p'range loop
            if p(i)='1' then return true; end if;
        end loop;
        return false;
    end function;

    -- Procura por pedidos ativos apenas nos andares que estão acima da posição atual.
    function busca_acima(atual: natural; p: std_logic_vector) return integer is
    begin
        for f in 0 to N-1 loop
            if f > atual and p(f)='1' then return f; end if;
        end loop;
        return -1;
    end function;

    -- Procura por pedidos ativos apenas nos andares que estão abaixo da posição atual.
    function busca_abaixo(atual: natural; p: std_logic_vector) return integer is
    begin
        for f in N-1 downto 0 loop
            if f < atual and p(f)='1' then return f; end if;
        end loop;
        return -1;
    end function;

begin
    -- Este bloco de decisão reavalia a rota instantaneamente sempre que um botão é apertado ou o elevador se move.
    process(andar_atual, dir_entrada, pend_int, pend_ext)
        variable a_atual : natural;
        variable acima_i, abaixo_i : integer;
        variable alvo_temp : integer;
        variable pend_total : std_logic_vector(N-1 downto 0);
    begin
        a_atual := to_integer(andar_atual);
        
        -- Une os pedidos de dentro e de fora. Para o cálculo da melhor rota, 
        -- o sistema trata todos os pedidos com a mesma importância.
        pend_total := pend_int or pend_ext;

        if not tem_alguma(pend_total) then
            -- Se ninguém chamou o elevador, ele permanece parado onde está.
            tem_destino <= '0';
            destino <= andar_atual;
            dir_saida <= DIR_PARADA;
        else
            -- Identifica qual o pedido mais próximo acima e qual o mais próximo abaixo.
            acima_i := busca_acima(a_atual, pend_total);
            abaixo_i := busca_abaixo(a_atual, pend_total);

            if acima_i = -1 and abaixo_i = -1 then
                alvo_temp := a_atual;
                dir_saida <= DIR_PARADA;

            elsif dir_entrada = DIR_SOBE then
                -- Se o elevador já está subindo, continua a subir enquanto houver pedidos acima.
                if acima_i /= -1 then
                    alvo_temp := acima_i;
                    dir_saida <= DIR_SOBE;
                else
                    -- Se não há mais ninguém acima, ele inverte a direção para atender quem está abaixo.
                    alvo_temp := abaixo_i;
                    dir_saida <= DIR_DESCE;
                end if;

            elsif dir_entrada = DIR_DESCE then
                -- Se o elevador já está descendo, continua a descer enquanto houver pedidos abaixo.
                if abaixo_i /= -1 then
                    alvo_temp := abaixo_i;
                    dir_saida <= DIR_DESCE;
                else
                    -- Se não há mais ninguém abaixo, ele inverte a direção para atender quem está acima.
                    alvo_temp := acima_i;
                    dir_saida <= DIR_SOBE;
                end if;

            else 
                -- Se o elevador estiver parado e surgirem novos pedidos, o sistema faz um cálculo 
                -- simples de distância e escolhe o andar que estiver mais perto para economizar tempo.
                if acima_i = -1 then
                    alvo_temp := abaixo_i;
                    dir_saida <= DIR_DESCE;
                elsif abaixo_i = -1 then
                    alvo_temp := acima_i;
                    dir_saida <= DIR_SOBE;
                else
                    if (acima_i - a_atual) <= (a_atual - abaixo_i) then
                        alvo_temp := acima_i;
                        dir_saida <= DIR_SOBE;
                    else
                        alvo_temp := abaixo_i;
                        dir_saida <= DIR_DESCE;
                    end if;
                end if;
            end if;

            -- Envia a decisão final para o controlador principal.
            tem_destino <= '1';
            destino <= to_unsigned(alvo_temp, destino'length);
        end if;
    end process;
end architecture;