\ for STM8s0003 > QN8027

\ At power up freq stored in $4000 is used (EEPROM)
 
\ I2C interface to QN8027 FM chip with external pull ups

\ An I2C interface transfer is:
\ START condition, a command byte and data bytes, 
\                  each byte has a followed ACK (or NACK) bit, 
\ ends with STOP condition.
\ Idle state is Clk:H Data:H
\ During transmission of data Clk idle's LOW

\ as master STM8 always provides clock pulses
\ By setting bit in DDR we turn pin into an output. 
\ With 0 in ODR this pulls pin low
\ Therefore, when slave is sending ODR = 1

\ Command for QN8027 is a register address
\ ************ INCLude I2C Lib here *****************************

4 CONSTANT _CLK \ _I2C Clock = PB4
5 CONSTANT _DATA \ _I2C _DATA = PB5

$5005 CONSTANT PB_ODR
$5006 CONSTANT PB_IDR
$5007 CONSTANT PB_DDR
$5008 CONSTANT PB_CR1
$5009 CONSTANT PB_CR2
$50D1 CONSTANT WWDG_CR

NVM
: ]B? ( c-addr bit -- f )
     $905F , 2* $7201 + , , $0290 , $5A5A , $5AFF , ]
; IMMEDIATE
: ]B! ( 1|0 addr bit -- )
  ROT 0= 1 AND SWAP 2* $10 + + $72 C, C, , ]
; IMMEDIATE 
: ]C! $35 C, SWAP C, , ] ; IMMEDIATE

VARIABLE XTAL
   
: *10us  ( n -- )  \  delay n * 10us
   1- FOR [
      $A62B ,    \      LD    A,#42
      $4A  C,    \ 1$:  DEC   A
      $26FD ,    \      JRNE  1$
   ] NEXT
   ;
: ms  ( n -- )  \  delay n ms
   1- FOR 100 *10us NEXT
;   

: WAIT ( -- ) 1 dup 2drop ; 

: SCL1 ( -- ) [ 0 PB_DDR _CLK ]B! WAIT ;
: SCL0 ( -- ) [ 1 PB_DDR _CLK ]B! ( WAIT )  ; 
\ wait not reqd. Data always set with wait before next SCL1
: SDA1 ( -- ) [ 0 PB_DDR _DATA ]B! WAIT ;
: SDA0 ( -- ) [ 1 PB_DDR _DATA ]B! WAIT ;
: SDA? ( -- f ) [ PB_IDR _DATA ]B? ;

: I2C-START ( -- ) \ with SCL high, change SDA from 1 to 0
  SDA0 SCL0 ;
: I2C-STOP ( -- ) \ with SCL high, change SDA from 0 to 1
  SDA0 SCL1 SDA1 ;

: nak? ( -- f ) \ in: SDA=? SCL=0  out: SDA=1 SCL=0
\ Return a true/false flag if an NACK/ACK was received from the I2C Bus.
  SDA1 \ allow slave to pull low if ack sent
  SCL1 SDA? SCL0 ;

: ?I.ACK ( -- ) \ reset if no I.ACK received
   nak?  
   IF  [ $80 WWDG_CR ]C!  \ FORCE reset IF NO ack
   THEN
;
: Ic! ( byte -- )
\ Send a byte to the I2C Bus. Exit with SCL low 
  7 FOR 
     DUP $80 AND 
     IF     SDA1 
     ELSE   SDA0 
     THEN   
     2*
     SCL1 SCL0 
  NEXT  
  DROP 
;
: Ic!? Ic! ?I.ACK ;

: Ic@ ( -- byte ) \ Receive a byte from the I2C Bus.
   SDA1  \ allow slave to set
   0 
   8 0 DO 
      2* SCL1 SDA? SCL0 
      ABS \ needed. SDA? returns a flag -1|0
      OR 
   LOOP
;
: I.NAK ( -- ) \ in: SDA=? SCL=0  out: SDA=1 SCL=0
\ Send an NAK to the I2C Bus.
  SDA1 SCL1 SCL0 ;

: I.ACK ( -- ) \ in: SDA=? SCL=0  out: SDA=1 SCL=0
\ Send an ACK to the I2C Bus.
   SDA0 SCL1 SCL0 ;

: IC@A IC@ I.ACK ;
: I.init ( -- )
\ Initialize the I2C Bus interface
\ set output registers low AND HIGH SINK ON
  [ 0 PB_ODR _CLK ]B! [ 1 PB_CR1 _CLK ]B!
  [ 0 PB_ODR _DATA ]B! [ 1 PB_CR1 _DATA ]B!
  SDA1 SCL1  \ Idle state so enable I2C pins as inputs
  \ Send a START/STOP sequence. 
  \ Otherwise the first bus access fails with an ACK error
  I2C-START  
  $1 Ic! I.ACK I2C-STOP
;

RAM 

\ ************************QN8027 STUFF ******************************

$58 CONSTANT CHIPID \ default "CHIP ID" shifted left
    CHIPID 1+ CONSTANT CHIPID.RX
$00 CONSTANT SYSTEM 
$01 CONSTANT CH1 \ Lower 8 bits of 10-bit channel index.
$02 CONSTANT GPLT \ Audio controls, gain of TX pilot frequency deviation
$03 CONSTANT REG_XTL \ XCLK pin control.
$04 CONSTANT REG_VGA \ TX mode input impedance, crystal frequency setting.
$05 CONSTANT CID1 \ Device ID numbers.
$06 CONSTANT CID2 \ Device ID numbers.
$07 CONSTANT STATUS \ Device status indicators.
$08 CONSTANT RDSD0 \ RDS data byte 0.
$09 CONSTANT RDSD1 
$0A CONSTANT RDSD2
$0B CONSTANT RDSD3 
$0C CONSTANT RDSD4 
$0D CONSTANT RDSD5 
$0E CONSTANT RDSD6 
$0F CONSTANT RDSD7 
$10 CONSTANT PAC \ PA output power target control.
$11 CONSTANT FDEV \ Specify total TX frequency deviation.
$12 CONSTANT RDS \ Specify RDS frequency deviation, RDS mode selection.                   

NVM
: TX_START I2C-START CHIPID Ic!? ;
: RX_START I2C-START CHIPID.RX Ic!? ;
: RX_STOP I.NAK I2C-STOP ;

VARIABLE DELAYMS  
$4000 CONSTANT FREQ

: >QN ( C REG -- ) \ Send ONE byte of DATA to QN8027 from Stack
   TX_START 
   IC!? \ ADDRESS SENT
   IC!? \ DATA SENT
   I2C-STOP
;

: Freq>QN ( n --- ) \ store freq eg 9610
   7600 - 5 /
   DUP $FF AND SWAP EXG $FF AND \  n -- nl nh
   $20 OR   \ enable transmit, no mute
   SYSTEM >QN \ start tX, RDS and set freq
   CH1 >QN
;
: FREQ! ( n -- ) \ stored freq at turn on in eeprom
   ULOCK
   $4000 !
   LOCK
;

: T.ON ( -- ) \ turn on device
   I.INIT
   $c0 SYSTEM >QN \ RESET and PREPARE FOR RECAL
   XTAL @ 12 = 
   IF $32 \ Using a 12Mhz Xtal 
   ELSE $B2 \ Using a 24Mhz Xtal 
   THEN
   REG_VGA >QN \ SAVE BYTE
   $B9 GPLT >QN    \ 75kHz pre-emphasis, never stop TX
   $86 RDS >QN     \ RDS enabled and dev set
\ Default on reset shown by **, I had no need to resend   
\ **  $81 FDEV >QN    \ 75kHz deviation
\ **  $7F PAC >QN
\ **  $10 REG_XTL >QN \ clock source set
   $0  SYSTEM >QN   \ calibration called
\ Now send bytes to finish setup   
   FREQ @ FREQ>QN
   DELAYMS @ MS
;

: QN> ( n -- c ) \ fetch register n and save on stack
   TX_START IC!? I2C-STOP
   RX_START 
   IC@  
   RX_STOP \ includes a NAK
;

RAM

: MAIN
   24 XTAL !
   50 DELAYMS !
   T.ON
;   
