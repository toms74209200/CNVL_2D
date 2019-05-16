-- =====================================================================
--  Title       : 2D liner convolution(Laplacian filter)
--
--  File Name   : CNVL_2D.vhd
--  Project     : Sample
--  Block       :
--  Tree        :
--  Designer    : toms74209200 <https://github.com/toms74209200>
--  Created     : 2019/04/26
--  Copyright   : 2019 toms74209200
--  License     : MIT License.
--                http://opensource.org/licenses/mit-license.php
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use work.PAC_ADD.all;

entity CNVL_2D is
    generic(
        W           : integer := 32;                            -- Image data width
        H           : integer := 32                             -- Image data height
    );
    port(
    -- System --
        nRST        : in    std_logic;                          --(n) Reset
        CLK         : in    std_logic;                          --(p) Clock

    -- Control --
        WR          : in    std_logic;                          --(p) Raw data input enable
        RD          : out   std_logic;                          --(p) Convolution data output timing
        WDAT        : in    std_logic_vector(7 downto 0);       --(p) Raw data
        RDAT        : out   std_logic_vector(7 downto 0)        --(p) Convolution data
        );
end CNVL_2D;

architecture RTL of CNVL_2D is

-- Internal signal --
-- Write sequence --
signal wp_cnt           : integer range 0 to 3;                 --(p) Line buffer control pointer
signal wh_cnt           : integer range 0 to H-1;               --(p) Raw image row bit count
signal ww_cnt           : integer range 0 to W;                 --(p) Raw image column bit count

-- Read sequence --
signal cnvl_busy        : std_logic;                            --(p) Convolution busy flag
signal rp_cnt           : integer range 0 to 3;                 --(p) Line buffer control pointer
signal rh_cnt           : integer range 0 to H-1;               --(p) Convolution image row bit count
signal rw_cnt           : integer range 0 to W+1;               --(p) Convolution image column bit count
signal rwo_cnt          : integer range 0 to W-1;               --(p) Convolution image column bit output count
signal cell_cnt         : integer range 0 to 3;                 --(p) Convolution cell column bit count
signal rd_i             : std_logic;                            --(p) Convolution data output assert
signal rdat_i           : std_logic_vector(WDAT'length*2+3 downto 0);   --(p) Convolution data

-- Line buffer(W+2 length / 8bit color) --
type LBF_TYP            is array (0 to W+1) of std_logic_vector(7 downto 0);
signal lbf0             : LBF_TYP;                              --(p) Line buffer
signal lbf1             : LBF_TYP;                              --(p) Line buffer
signal lbf2             : LBF_TYP;                              --(p) Line buffer
signal lbf3             : LBF_TYP;                              --(p) Line buffer

-- Convolution cell --
type CNVL_TYP           is array (0 to 2, 0 to 3) of std_logic_vector(7 downto 0);
signal cnvl_cell        : CNVL_TYP;                             --(p) Convolution cell

-- Kernel cell --
type KRNL_TYP is array (0 to 8) of std_logic_vector(7 downto 0);
signal krnl_cell        : KRNL_TYP;                             --(p) Kernel cell

-- Calculation cell --
type WGHT_TYP is array (0 to 8) of std_logic_vector(WDAT'length*2-1 downto 0);
signal wght_cell        : WGHT_TYP;                             --(p) Calculation cell

-- Summation cell --
signal sum_cell_00      : std_logic_vector(WDAT'length*2 downto 0);   --(p) Summation cell
signal sum_cell_01      : std_logic_vector(WDAT'length*2 downto 0);   --(p) Summation cell
signal sum_cell_02      : std_logic_vector(WDAT'length*2 downto 0);   --(p) Summation cell
signal sum_cell_03      : std_logic_vector(WDAT'length*2 downto 0);   --(p) Summation cell
signal sum_cell_10      : std_logic_vector(WDAT'length*2+1 downto 0);     --(p) Summation cell
signal sum_cell_11      : std_logic_vector(WDAT'length*2+1 downto 0);     --(p) Summation cell
signal sum_cell_20      : std_logic_vector(WDAT'length*2+2 downto 0);   --(p) Summation cell
signal sum_cell_21      : std_logic_vector(WDAT'length*2+2 downto 0);   --(p) Summation cell

begin
--
-- ***********************************************************
--  Line buffer control pointer
-- ***********************************************************
process (CLK, nRST) begin
    if (nRST = '0') then
        wp_cnt <= 0;
    elsif (CLK'event and CLK = '1') then
        if (WR = '1') then
            if (ww_cnt = W-1) then
                if (wh_cnt = H-1) then
                    wp_cnt <= wp_cnt;
                else
                    if (wp_cnt = 3) then
                        wp_cnt <= 0;
                    else
                        wp_cnt <= wp_cnt + 1;
                    end if;
                end if;
            end if;
        elsif (cnvl_busy = '1') then
            if (wh_cnt = H-1 and rh_cnt = H-1 and rw_cnt = W-1) then
                wp_cnt <= 0;
            end if;
        end if;
    end if;
end process;


-- ***********************************************************
--  Raw image row bit count
-- ***********************************************************
process (CLK, nRST) begin
    if (nRST = '0') then
        wh_cnt <= 0;
    elsif (CLK'event and CLK = '1') then
        if (WR = '1') then
            if (ww_cnt = W-1) then
                if (wh_cnt = H-1) then
                    wh_cnt <= wh_cnt;
                else
                    wh_cnt <= wh_cnt + 1;
                end if;
            end if;
        elsif (cnvl_busy = '1') then
            if (wh_cnt = H-1 and rh_cnt = H-1 and rw_cnt = W-1) then
                wh_cnt <= 0;
            end if;
        end if;
    end if;
end process;


-- ***********************************************************
--  Raw image column bit count
-- ***********************************************************
process (CLK, nRST) begin
    if (nRST = '0') then
        ww_cnt <= 0;
    elsif (CLK'event and CLK = '1') then
        if (WR = '1') then
            if (wh_cnt = H-1) then
                if (ww_cnt = W-1) then
                    ww_cnt <= ww_cnt;
                else
                    ww_cnt <= ww_cnt + 1;
                end if;
            else
                if (ww_cnt = W-1) then
                    ww_cnt <= 0;
                else
                    ww_cnt <= ww_cnt + 1;
                end if;
            end if;
        elsif (cnvl_busy = '1') then
            if (wh_cnt = H-1 and rh_cnt = H-1 and rw_cnt = W-1) then
                ww_cnt <= 0;
            end if;
        end if;
    end if;
end process;


-- ***********************************************************
--  Line buffer
-- ***********************************************************
process (CLK) begin
    if (CLK'event and CLK = '1') then
        if (WR = '1') then
            if (wp_cnt = 0) then
                lbf0(ww_cnt+1) <= WDAT;
            end if;
        end if;
    end if;
end process;

process (CLK) begin
    if (CLK'event and CLK = '1') then
        if (WR = '1') then
            if (wp_cnt = 1) then
                lbf1(ww_cnt+1) <= WDAT;
            end if;
        end if;
    end if;
end process;

process (CLK) begin
    if (CLK'event and CLK = '1') then
        if (WR = '1') then
            if (wp_cnt = 2) then
                lbf2(ww_cnt+1) <= WDAT;
            end if;
        end if;
    end if;
end process;

process (CLK) begin
    if (CLK'event and CLK = '1') then
        if (WR = '1') then
            if (wp_cnt = 3) then
                lbf3(ww_cnt+1) <= WDAT;
            elsif (wh_cnt = 0) then
                lbf3(ww_cnt+1) <= (others => '0');
            end if;
        end if;
    end if;
end process;


-- ***********************************************************
--  Convolution busy flag
-- ***********************************************************
process (CLK, nRST) begin
    if (nRST = '0') then
        cnvl_busy <= '0';
    elsif (CLK'event and CLK = '1') then
        if (rh_cnt = H-1 and rwo_cnt = W-1) then
            cnvl_busy <= '0';
        elsif (wh_cnt = H-1 and ww_cnt = W-1) then
            cnvl_busy <= '1';
        elsif (wh_cnt-1 > rh_cnt) then
            if (wp_cnt = rp_cnt-1) then
                cnvl_busy <= '1';
            elsif (wp_cnt = 3 and rp_cnt = 0) then
                cnvl_busy <= '1';
            else
                cnvl_busy <= '0';
            end if;
        else
            cnvl_busy <= '0';
        end if;
    end if;
end process;


-- ***********************************************************
--  Line buffer control pointer
-- ***********************************************************
process (CLK, nRST) begin
    if (nRST = '0') then
        rp_cnt <= 0;
    elsif (CLK'event and CLK = '1') then
        if (rh_cnt = H-1 and rwo_cnt = W-1) then
            rp_cnt <= 0;
        elsif (cnvl_busy = '1') then
            if (rwo_cnt = W-1) then
                if (rp_cnt = 3) then
                    rp_cnt <= 0;
                else
                    rp_cnt <= rp_cnt + 1;
                end if;
            end if;
        end if;
    end if;
end process;


-- ***********************************************************
--  Raw image row bit count
-- ***********************************************************
process (CLK, nRST) begin
    if (nRST = '0') then
        rh_cnt <= 0;
    elsif (CLK'event and CLK = '1') then
        if (rwo_cnt = W-1) then
            if (rh_cnt = H-1) then
                rh_cnt <= 0;
            else
                rh_cnt <= rh_cnt + 1;
            end if;
        end if;
    end if;
end process;


-- ***********************************************************
--  Raw image column bit count
-- ***********************************************************
process (CLK, nRST) begin
    if (nRST = '0') then
        rw_cnt <= 0;
    elsif (CLK'event and CLK = '1') then
        if (cnvl_busy = '1') then
            if (rw_cnt = W+1) then
                if (rwo_cnt = W-1) then
                    rw_cnt <= 0;
                else
                    rw_cnt <= rw_cnt;
                end if;
            else
                rw_cnt <= rw_cnt + 1;
            end if;
        elsif (rw_cnt > 0) then
            if (rw_cnt = W+1) then
                if (rwo_cnt = W-1) then
                    rw_cnt <= 0;
                else
                    rw_cnt <= rw_cnt;
                end if;
            else
                rw_cnt <= rw_cnt + 1;
            end if;
        else
            rw_cnt <= 0;
        end if;
    end if;
end process;


-- ***********************************************************
--  Convolution cell column bit count
-- ***********************************************************
process (CLK, nRST) begin
    if (nRST = '0') then
        cell_cnt <= 0;
    elsif (CLK'event and CLK = '1') then
        if (cnvl_busy = '1') then
            if (cell_cnt = 3) then
                cell_cnt <= 0;
            else
                cell_cnt <= cell_cnt + 1;
            end if;
        else
            cell_cnt <= 0;
        end if;
    end if;
end process;


-- ***********************************************************
--  Convolution cell register
-- ***********************************************************
process (CLK) begin
    if (CLK'event and CLK = '1') then
        if (rh_cnt = 0) then
            cnvl_cell(0, cell_cnt) <= (others => '0');
            cnvl_cell(1, cell_cnt) <= lbf0(rw_cnt);
            cnvl_cell(2, cell_cnt) <= lbf1(rw_cnt);
        elsif (rh_cnt = H-1) then
            case (rp_cnt) is
                when 0 =>
                    cnvl_cell(0, cell_cnt) <= lbf3(rw_cnt);
                    cnvl_cell(1, cell_cnt) <= lbf0(rw_cnt);
                    cnvl_cell(2, cell_cnt) <= (others => '0');
                when 1 =>
                    cnvl_cell(0, cell_cnt) <= lbf0(rw_cnt);
                    cnvl_cell(1, cell_cnt) <= lbf1(rw_cnt);
                    cnvl_cell(2, cell_cnt) <= (others => '0');
                when 2 =>
                    cnvl_cell(0, cell_cnt) <= lbf1(rw_cnt);
                    cnvl_cell(1, cell_cnt) <= lbf2(rw_cnt);
                    cnvl_cell(2, cell_cnt) <= (others => '0');
                when 3 =>
                    cnvl_cell(0, cell_cnt) <= lbf2(rw_cnt);
                    cnvl_cell(1, cell_cnt) <= lbf3(rw_cnt);
                    cnvl_cell(2, cell_cnt) <= (others => '0');
                when others =>
                    cnvl_cell(0, cell_cnt) <= cnvl_cell(0, cell_cnt);
                    cnvl_cell(1, cell_cnt) <= cnvl_cell(1, cell_cnt);
                    cnvl_cell(2, cell_cnt) <= cnvl_cell(2, cell_cnt);
            end case;
        else
            case (rp_cnt) is
                when 0 =>
                    cnvl_cell(0, cell_cnt) <= lbf3(rw_cnt);
                    cnvl_cell(1, cell_cnt) <= lbf0(rw_cnt);
                    cnvl_cell(2, cell_cnt) <= lbf1(rw_cnt);
                when 1 =>
                    cnvl_cell(0, cell_cnt) <= lbf0(rw_cnt);
                    cnvl_cell(1, cell_cnt) <= lbf1(rw_cnt);
                    cnvl_cell(2, cell_cnt) <= lbf2(rw_cnt);
                when 2 =>
                    cnvl_cell(0, cell_cnt) <= lbf1(rw_cnt);
                    cnvl_cell(1, cell_cnt) <= lbf2(rw_cnt);
                    cnvl_cell(2, cell_cnt) <= lbf3(rw_cnt);
                when 3 =>
                    cnvl_cell(0, cell_cnt) <= lbf2(rw_cnt);
                    cnvl_cell(1, cell_cnt) <= lbf3(rw_cnt);
                    cnvl_cell(2, cell_cnt) <= lbf0(rw_cnt);
                when others =>
                    cnvl_cell(0, cell_cnt) <= cnvl_cell(0, cell_cnt);
                    cnvl_cell(1, cell_cnt) <= cnvl_cell(1, cell_cnt);
                    cnvl_cell(2, cell_cnt) <= cnvl_cell(2, cell_cnt);
            end case;
        end if;
    end if;
end process;


-- ***********************************************************
--  Convolution(Laplacian filter)
-- ***********************************************************
-- Kernel --
-- | 1  1  1 |
-- | 1 -8  1 |
-- | 1  1  1 |

krnl_cell(0) <= B"0000_0001";
krnl_cell(1) <= B"0000_0010";
krnl_cell(2) <= B"0000_0001";

krnl_cell(3) <= B"0000_0010";
krnl_cell(4) <= B"0000_0100";
krnl_cell(5) <= B"0000_0010";

krnl_cell(6) <= B"0000_0001";
krnl_cell(7) <= B"0000_0010";
krnl_cell(8) <= B"0000_0001";

-- Cell culclacion --
process (CLK, nRST) begin
    if (nRST = '0') then
        wght_cell(0) <= (others => '0');
        wght_cell(1) <= (others => '0');
        wght_cell(2) <= (others => '0');
        wght_cell(3) <= (others => '0');
        wght_cell(4) <= (others => '0');
        wght_cell(5) <= (others => '0');
        wght_cell(6) <= (others => '0');
        wght_cell(7) <= (others => '0');
        wght_cell(8) <= (others => '0');
    elsif (CLK'event and CLK = '1') then
    -- row 1 --
        wght_cell(0) <= (krnl_cell(0)(7) & (cnvl_cell(0, cell_cnt+1) * krnl_cell(0)(6 downto 0)));
        wght_cell(1) <= (krnl_cell(1)(7) & (cnvl_cell(0, cell_cnt+2) * krnl_cell(1)(6 downto 0)));
        wght_cell(2) <= (krnl_cell(2)(7) & (cnvl_cell(0, cell_cnt+3) * krnl_cell(2)(6 downto 0)));
    -- row 2 --
        wght_cell(3) <= (krnl_cell(3)(7) & (cnvl_cell(1, cell_cnt+1) * krnl_cell(3)(6 downto 0)));
        wght_cell(4) <= (krnl_cell(4)(7) & (cnvl_cell(1, cell_cnt+2) * krnl_cell(4)(6 downto 0)));
        wght_cell(5) <= (krnl_cell(5)(7) & (cnvl_cell(1, cell_cnt+3) * krnl_cell(5)(6 downto 0)));
    -- row 3 --
        wght_cell(6) <= (krnl_cell(6)(7) & (cnvl_cell(2, cell_cnt+1) * krnl_cell(6)(6 downto 0)));
        wght_cell(7) <= (krnl_cell(7)(7) & (cnvl_cell(2, cell_cnt+2) * krnl_cell(7)(6 downto 0)));
        wght_cell(8) <= (krnl_cell(8)(7) & (cnvl_cell(2, cell_cnt+3) * krnl_cell(8)(6 downto 0)));
    end if;
end process;

-- Summation --
sum_cell_00 <= add_signed(wght_cell(0), wght_cell(1));
sum_cell_01 <= add_signed(wght_cell(2), wght_cell(3));
sum_cell_02 <= add_signed(wght_cell(4), wght_cell(5));
sum_cell_03 <= add_signed(wght_cell(6), wght_cell(7));

sum_cell_10 <= add_signed(sum_cell_00, sum_cell_01);
sum_cell_11 <= add_signed(sum_cell_02, sum_cell_03);

sum_cell_20 <= add_signed(sum_cell_10, sum_cell_11);
sum_cell_21 <= (wght_cell(8)(wght_cell(8)'left) & "000" & wght_cell(8)(wght_cell(8)'left-1 downto 0));

process (CLK, nRST) begin
    if (nRST = '0') then
        rdat_i <= (others => '0');
    elsif (CLK'event and CLK = '1') then
        rdat_i <= add_signed(sum_cell_20, sum_cell_21);
    end if;
end process;


-- ***********************************************************
--  Convolution image column bit output count
-- ***********************************************************
process (CLK, nRST) begin
    if (nRST = '0') then
        rwo_cnt <= 0;
    elsif (CLK'event and CLK = '1') then
        if (rd_i = '1') then
            if (rwo_cnt = W-1) then
                rwo_cnt <= 0;
            else
                rwo_cnt <= rwo_cnt + 1;
            end if;
        end if;
    end if;
end process;


-- ***********************************************************
--  Output assert
-- ***********************************************************
process (CLK, nRST) begin
    if (nRST = '0') then
        rd_i <= '0';
    elsif (CLK'event and CLK = '1') then
        if (rwo_cnt = W-1) then
            rd_i <= '0';
        elsif (cnvl_busy = '1') then
            if (rw_cnt < 4 and rwo_cnt = 0) then
                rd_i <= '0';
            else
                rd_i <= '1';
            end if;
        end if;
    end if;
end process;


-- ***********************************************************
--  Output data
-- ***********************************************************
RD <= rd_i;
RDAT <= rdat_i(7+4 downto 4);


end RTL;	-- CNVL_2D
