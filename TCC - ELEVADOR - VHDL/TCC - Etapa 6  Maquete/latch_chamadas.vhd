library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity latch_chamadas is
    generic (N: natural := 4);
    port (
        clk       : in std_logic;
        rst_n     : in std_logic;
        botao_int : in std_logic_vector(N-1 downto 0); -- Sinais dos botões do painel interno da cabine      
        botao_ext : in std_logic_vector(N-1 downto 0); -- Sinais dos botões localizados nos corredores       
        limpa_idx : in std_logic_vector(N-1 downto 0); -- Comando externo para apagar um pedido que já foi atendido
        pend_int  : out std_logic_vector(N-1 downto 0); -- Saída com a lista de pedidos internos salvos
        pend_ext  : out std_logic_vector(N-1 downto 0)  -- Saída com a lista de pedidos externos salvos
    );
end entity;

architecture rtl of latch_chamadas is
    signal p_int, p_ext : std_logic_vector(N-1 downto 0);
    signal last_int, last_ext : std_logic_vector(N-1 downto 0) := (others => '0');
    signal pulso_int, pulso_ext : std_logic_vector(N-1 downto 0);
begin
    -- Conecta a memória interna do chip às saídas do módulo.
    -- Isso permite que o resto do sistema leia os pedidos armazenados.
    pend_int <= p_int;
    pend_ext <= p_ext;

    -- Filtro de sinal lógico: Identifica o momento exato em que a chave/botão foi acionado. 
    -- Mantém-se inalterado pois esta lógica resolve tanto o problema das chaves travadas (Switches da cabine)
    -- quanto garante uma leitura limpa de um único clique para os botões físicos (Push-buttons da maquete).
    pulso_int <= botao_int and (not last_int);
    pulso_ext <= botao_ext and (not last_ext);

    process(clk)
    begin
        if rising_edge(clk) then
            -- Armazena o estado atual dos botões e chaves. 
            -- Essa informação será usada pelo filtro de sinal no próximo ciclo do relógio.
            last_int <= botao_int;
            last_ext <= botao_ext;
            
            if rst_n = '0' then
                p_int <= (others=>'0');
                p_ext <= (others=>'0');
            else
                -- Armazenamento contínuo dos pedidos. O comando 'or' adiciona uma nova chamada à lista.
                -- O comando 'not' apaga a anotação da memória exatamente no instante em que 
                -- o elevador avisa que chegou ao respectivo andar.
                p_int <= (p_int or pulso_int) and (not limpa_idx);
                p_ext <= (p_ext or pulso_ext) and (not limpa_idx);
            end if;
        end if;
    end process;
end architecture;