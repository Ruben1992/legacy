/* A game chooser for borgs
 * by: Christian Kroll
 * date: Thursday, 2008/03/16
 */

#include <stdlib.h>
#include <assert.h>
#include <inttypes.h>

// architecture dependent stuff
#include "../compat/pgmspace.h"

#include "menu.h"
#include "../config.h"
#include "../util.h"
#include "../pixel.h"
#include "../joystick/joystick.h"


extern game_descriptor_t _game_descriptors_start__[];
extern game_descriptor_t _game_descriptors_end__[];

// defines
#define MENU_ITEM_MAX (((unsigned int)_game_descriptors_end__ - (unsigned int)_game_descriptors_start__)/sizeof(game_descriptor_t))

#define MENU_WIDTH_ICON 8
#define MENU_HEIGHT_ICON 8
#define MENU_WIDTH_DELIMITER 2
#define MENU_POLL_INTERVAL 10
#define MENU_TIMEOUT_ITERATIONS 2000
#define MENU_WAIT_CHATTER 60
#define MENU_WAIT_INITIAL 40
#define MENU_WAIT_INCREMENT 0

#define MENU_NEXTITEM(item) ((item + 1) % MENU_ITEM_MAX)
#define MENU_PREVITEM(item) ((item + MENU_ITEM_MAX - 1) % MENU_ITEM_MAX)

void menu()
{
	if (MENU_ITEM_MAX != 0)
	{
		// don't let WAIT() query fire button to prevent endless circular jumps
		waitForFire = 0;

		clear_screen(0);

		// wait as long as "fire" is pressed to prevent unwanted selections
		while (JOYISFIRE)
		{
			wait(MENU_POLL_INTERVAL);
		}

		// set initial menu item
		static uint8_t miSelection = 0;
		// scroll in currently selected menu item
		menu_animate(MENU_PREVITEM(miSelection), MENU_DIRECTION_LEFT);

		uint16_t nMenuIterations= MENU_TIMEOUT_ITERATIONS;

		while (1)
		{
			// the user has made her/his choice
			if (JOYISFIRE)
			{
				// prevent unwanted selections
				while (JOYISFIRE)
				{
					wait(MENU_POLL_INTERVAL);
				}
				// work against the chatter effects of dump joysticks
				wait(MENU_WAIT_CHATTER);

				// call corresponding function

				_game_descriptors_start__[miSelection].run();

				break;

			}
			// change selected item and do some scrolling
			else if (JOYISRIGHT)
			{
				menu_animate(miSelection, MENU_DIRECTION_LEFT);
				miSelection = MENU_NEXTITEM(miSelection);
				nMenuIterations = MENU_TIMEOUT_ITERATIONS;
			}
			else if (JOYISLEFT)
			{
				menu_animate(miSelection, MENU_DIRECTION_RIGHT);
				miSelection = MENU_PREVITEM(miSelection);
				nMenuIterations = MENU_TIMEOUT_ITERATIONS;
			}
			// exit menu
			else if (JOYISUP)
			{
				break;
			}
			// return if timeout is reached
			else
			{
				wait(MENU_POLL_INTERVAL);
				if (--nMenuIterations == 0)
					break;
			}
		}

		waitForFire = 1;
	}
	return;
}


uint8_t menu_getIconPixel(uint8_t item, int8_t x, int8_t y)
{
	// is x within the icon or do we have reached the delimiter?
	if (x < MENU_WIDTH_ICON)
	{
		// return pixel
		return (0x80 >> x) &
			pgm_read_word(&_game_descriptors_start__[item].icon[y]);
	}
	else
	{
		// delimiter
		return 0;
	}
}

void menu_animate(uint8_t miInitial, menu_direction_t direction)
{
	int16_t nWait= MENU_WAIT_INITIAL;

	// space between left border and the icon in the middle
	int8_t nWidthSide = (NUM_COLS - MENU_WIDTH_ICON) / 2;

	// determine the icon at the leftmost position
	uint8_t mi = miInitial + MENU_ITEM_MAX;
	int8_t nBack = nWidthSide / (MENU_WIDTH_ICON + MENU_WIDTH_DELIMITER);
	if ((nWidthSide % (MENU_WIDTH_ICON + MENU_WIDTH_DELIMITER)) != 0)
	{
		++nBack;
	}
	mi = (mi + MENU_ITEM_MAX - (nBack % MENU_ITEM_MAX)) % MENU_ITEM_MAX;

	// start and stop offsets for the scrolling icons (both are 0 for stills)
	int8_t nStart, nStop;
	if (direction == MENU_DIRECTION_STILL)
	{
		nStart = 0;
		nStop = 0;
	}
	else
	{
		nStart = 1;
		nStop = MENU_WIDTH_ICON + MENU_WIDTH_DELIMITER;
	}

	// draw menu screen for each offset within the nStart/nStop range
	int8_t i;
	for (i = nStart; i <= nStop; ++i)
	{
		int8_t nOffset;
		if (direction == MENU_DIRECTION_LEFT)
			nOffset = i;
		else
			nOffset = -i;

		// offset of the left most icon if it is cut by the left border
		int8_t nInitialSideOffset = (((MENU_WIDTH_ICON + MENU_WIDTH_DELIMITER)
		        - (nWidthSide % (MENU_WIDTH_ICON + MENU_WIDTH_DELIMITER)))
		        + nOffset + (MENU_WIDTH_ICON + MENU_WIDTH_DELIMITER))
		        % (MENU_WIDTH_ICON + MENU_WIDTH_DELIMITER);

		// an initial side offset of 0 means the leftmost icon was changed 
		// if we are scrolling to the left, increment value for leftmost item 
		if (direction == MENU_DIRECTION_LEFT)
		{
			if (nInitialSideOffset == 0)
			{
				mi = MENU_NEXTITEM(mi);
			}
		}

		// draw the icons from the leftmost position (line by line)
		int8_t y;
		for (y = 0; y < MENU_HEIGHT_ICON; ++y)
		{
			uint8_t miCurrent = mi;
			int8_t nIconOffset = nInitialSideOffset;
			int8_t x;
			for (x = 0; x < NUM_COLS; ++x)
			{
				int8_t nPixel = menu_getIconPixel(miCurrent, nIconOffset, y);

				menu_setpixel(x, ((NUM_ROWS - MENU_HEIGHT_ICON) / 2) + y,
				        nPixel);
				if (++nIconOffset >= (MENU_WIDTH_ICON + MENU_WIDTH_DELIMITER))
				{
					nIconOffset = 0;
					miCurrent = MENU_NEXTITEM(miCurrent);
				}
			}
		}

		// an initial side offset of 0 means the leftmost icon was changed 
		// if we are scrolling to the right, decrement value for leftmost item 
		if (direction == MENU_DIRECTION_RIGHT)
		{
			if (nInitialSideOffset == 0)
			{
				mi = MENU_PREVITEM(mi);
			}
		}

		// wait between the frames so that the animation can be seen
		wait(nWait);
		// animation speed can be throtteled
		nWait += MENU_WAIT_INCREMENT;
	}
}

void menu_setpixel(int8_t x, int8_t y, int8_t isSet)
{
	uint8_t nColor;

	// mirror mirror on the wall, what's the quirkiest API of them all...
	x = NUM_COLS - 1 - x;
	uint8_t nMiddle = (NUM_COLS - MENU_WIDTH_ICON) / 2;

	if (isSet != 0)
	{
		if ((x >= nMiddle - MENU_WIDTH_DELIMITER) && (x < (nMiddle
		        + MENU_WIDTH_ICON + MENU_WIDTH_DELIMITER)))
		{
			nColor = 3;
		}
		else if ((x == (nMiddle - MENU_WIDTH_DELIMITER - 1)) || (x == (nMiddle
		        + MENU_WIDTH_ICON + MENU_WIDTH_DELIMITER)))
		{
			nColor = 2;
		}
		else
		{
			nColor = 1;
		}
	}
	else
	{
		nColor = 0;
	}

	setpixel((pixel){x, y}, nColor);
}

