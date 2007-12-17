//2 AXIS ACCELEROMETER ABSOLUTE ANGLE TEST - HANSI

#include <setjmp.h>
#include <avr/interrupt.h>
#include <avr/pgmspace.h>
#include <stdlib.h> 

#include "config.h"
#include "borg_hw.h"
#include "pixel.h"
#include "util.h"

// SENSOR IS AN ADXL202
// +-2g, 12,5%DTY/g

//the current gravity value in duty cycle length
volatile uint16_t gValue[2];
//the current period length
volatile uint16_t gPeriod;
//measurement status variable
//bit 0 tells if a consecutive x and y measurement is ready
//bit 1 tells if a x measurement is ready, this is used internally
//as two consecutive measurements are necessary to determine the exact period
volatile uint8_t gStatus;
//saves the timer count when a measurement stops
volatile uint16_t gMeasureStop[2];

//the zero-g offset duty cycle
uint16_t gZero[2];
//the zero-g offset period
uint16_t gZeroPrd;

#define ACC_START GICR |= (1<<INT1)


void g_init(){
	//GICR |= (1<<INT0) | (1<<INT1);
	MCUCR |= (1<<ISC00) | (1<<ISC10); //Interrupt on any edge
	
	TCCR1B |= (1<<CS11);//Timer 1 to clk/8
}

//this is a PWM interrupt for the X axis of the acc sensor
//whenever this int measures a falling edge,
//it sets bit1 of the status flags
//this is used later, in the other interrupt, to calculate a precise period
ISR(SIG_INTERRUPT1){
	static uint16_t startx;
	
	//if no measurement is necessary, exit
	//(old values are still present, we don't want to override them)
	//if(gStatus & 1)
	//{
	//	return;
	//}
	
	//int now turns itself off at the end
	
	//PWM pin goes high
	if(!(PIND & (1<<PD3)))
	{
		//save start position
		startx = TCNT1;
		
		gStatus |= 2;
	}
	else if(gStatus & 2)
	{	
		//save stop timer
		gMeasureStop[0] = TCNT1;
		
		//save duty cycle length in counts
		gValue[0] = (gMeasureStop[0] - startx);
		
		gStatus &= ~2;
		
		//turn off this int
		GICR &= ~(1<<INT1);
		//turn on the other int
		GICR |= (1<<INT0);
	}
}

//this is a PWM interrupt
//it measures the y-axis pwm pulse width
//this interrupt saves the current timer value on the falling edge
//this can be used by user software, to calculate a very precise period,
//as the distance between the centers of the X and Y pulses are the period
ISR(SIG_INTERRUPT0){
	static uint16_t starty;
	
	//if no measurement is necessary, exit
	//(this interrupt shall only measure AFTER the x-axis interrupt has measured a pulse width)
	//if(!(gStatus & 2))
	//{
	//	return;
	//}
	
	//int is now executed on demand only
	
	//PWM pin goes high
	if(!(PIND & (1<<PD2)))
	{
		//save start position
		starty = TCNT1;
		
		gStatus |= 2;
	}
	else if(gStatus & 2)
	{
		//turn off this int
		GICR &= ~(1<<INT0);
		
		//save stop timer
		gMeasureStop[1] = TCNT1;
		
		//save duty cycle length in counts
		gValue[1] = (gMeasureStop[1] - starty);
		
		gStatus &= ~2;
		
		//set measurement ready
		gStatus |= 1;
	}
}

void g_calcPeriod()
{
	//if no measurement is waiting, we can't calc a period
	if(gStatus & 1)
	{
		//period is the distance between the centers of two consecutive x->y pulse width measurements
		gPeriod = (gMeasureStop[1] - (gValue[1] / 2)) - (gMeasureStop[0] - (gValue[0] / 2));
	}
}

void g_Calibrate()
{
	//other vars
	uint8_t i;
	
	//averaging variables
	uint32_t gZeroAvg[2];
	uint32_t gZeroPrdAvg;
	
	//init vars
	gZeroAvg[0] = 0;
	gZeroAvg[1] = 0;
	gZeroPrdAvg = 0;
	
	//reset measurement ready flag
	gStatus &= ~1;
	//fire the int up
	ACC_START;
	
	//accelerometer calibration
	//average the zero-g duty cycle and period
	for(i = 0; i < 8; i++)
	{
		//wait for x and y interrupt to complete
		while(!(gStatus & 1));
		
		//make a period
		g_calcPeriod();
		
		gZeroAvg[0] += gValue[0];
		gZeroAvg[1] += gValue[1];
		gZeroPrdAvg += gPeriod;

		//reset measurement ready flag
		gStatus &= ~1;
		//fire the int u
		ACC_START;
	}
	
	//average
	gZero[0] = gZeroAvg[0] / 8;
	gZero[1] = gZeroAvg[1] / 8;
	gZeroPrd = gZeroPrdAvg / 8;
}

#define setpix(x,y,b) setpixel((pixel){x,y},b)

int main (void){
	//current gravity value
	int16_t gCurrent[2];
	
	//current zero offset calibration value
	uint16_t gCurZero[2];
	
	//point positions for drawing
	pixel myPix, oldPix;
	
	//other vars
    uint8_t i;
    
	//some mystic initialization
    DDRB |= (1<<1) | (2<<1);
    PORTB |= (1<<1);
    PORTB &= ~(2<<1);
	
	//borg and acc sensor initialization
	clear_screen(0);
	borg_hw_init();
    wait(100);
	g_init();
	sei();	
	
	//acc sensor datasheet says pwm outputs should be stable after 2ms...
	wait(10);
	
	//calibrate zero offset values
	g_Calibrate();
	
	//calculate current zero offset - once for now
	//fixme - this has to be re-calculated every once a while
	//but we would need a very precise period for that
	//formula is (gZero * PRECISE_ACTUAL_PERIOD) / calibrated period
	gCurZero[0] = (gZero[0] / gZeroPrd);
	gCurZero[1] = (gZero[1] / gZeroPrd);
    
	//loop to death
	while(1)
	{	
		//reset measurement flag to start a new cycle
		gStatus &= ~1;
		//fire the int up
		ACC_START;

		//wait for period end
		while(!(gStatus & 1));
		
		//calculate period
		//g_calcPeriod();
		
		//store current g value
		//note: this is a duty cycle in percent
		gCurrent[0] = ((int32_t)((int32_t)gValue[0] - gCurZero[0]) * 100) / gPeriod;
		
		//store current g value
		//note: this is a duty cycle in percent
		gCurrent[1] = ((int32_t)((int32_t)gValue[1] - gCurZero[1]) * 100) / gPeriod;
		
		//store old pixel position
		oldPix.x = myPix.x;
		oldPix.y = myPix.y;
		
		//calculate new pixel position
		//this borg has 10X and 8Y
		//the acc sensor has an average of 12,5%dty per g
		//1g should represent 90degree tilt in the given axis
		//we want the pixel to indicate the absolute tilt
		//this results in -12,5 = 0 x or y and +12,5 = max x or y
		
		//the formula scales up the 12,5 by factor 8 and rescales the result to fit the display
		myPix.x = 5 - ((int32_t)gCurrent[0] * 8 /*scale*/ * 5 /*half x*/) / (12.5 * 8 /*scale*/);
		myPix.y = 4 - ((int32_t)gCurrent[1] * 8 /*scale*/ * 4 /*half y*/) / (12.5 * 8 /*scale*/);

		//set pixels
		setpixel(oldPix,0);
		setpixel(myPix,3);

	}
}
