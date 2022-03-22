# nac-izone

These scripts are designed to integrate a C-Bus Network Automation Controller with the Airstream iZone 325 Climate Control System.

## Who can use this library?

To use these scripts you would need the following hardware:
* iZone Smart Air system https://izone.com.au/smart-air-conditioning/
* iZone Wifi Bridge https://izone.com.au/products/wifi-bridge/izone-open-connection-wi-fi-bridge/
* 5500NAC https://www.clipsal.com/products/detail?CatNo=5500NAC

The iZone Wifi Bridge and the 5500NAC need to be on the same local network.


## Why use this library?

* The iZone Wifi Bridge has no authentication and you should not expose it directly to the internet. This library places it behind the authentication of your Automation Controller.
* The iZone mobile app requires the use of a cloud service (iZone Worldwide Login).  This library keeps communication confined to your local network.
* The iZone mobile app and controllers have a specific UI that can't be customised.  This library allows the same HVAC functions to be presented and controlled in any way you desire using NAC visualisations.


## Installation

These steps assume you have logged into your NAC and navigated to "Configurator".

### 1/ Install the user library
* Select the "Scripting" tab in the purple menu bar.
* Select "User Libraries" and select "Add new library"
	* Script name: <mark>izone</mark>
	* Keep source: <mark>yes</mark>
	* Auto load library: <mark>no</mark>
	* Select "Save"
* Paste the contents of the file userlibrary_izone.lua into the code editor.
* **IMPORTANT**: Read all the comments!  Update the variables in the SCRIPT CONFIGURATION section as needed for your installation!
* Select "Save and close"

### 2/ Add the C-Bus Groups

The user library currently makes use of 11 Group Addresses (as described in the comments).  For each of these you must create the equivalent object in the NAC.

* Select the "Objects" tab in the purple menu bar.
* Select "Add new object"
	* Application - <mark>Heating</mark> (for example)
	* Group Address: click the + button to add a new one  
	* Keywords: <mark>izone_event</mark>
	* Log: <mark>no</mark>
* **IMPORTANT**: After creating the object, click the icon in the "Set Value" column and then on the resulting form simply hit the "Save" button again.  This is needed to work around a NAC bug (at least in firmware v1.0.,8) and initialise the object with a value of 0 instead of null.

Repeat as needed until all Group Address objects are created.  

### 3/ Install the event handler script
* Select "Event-based"
* Select "Add new script"
	* Script name: <mark>iZone Event Handler Script</mark>
	* Group address/keyword: <mark>izone_event</mark>
	* Active: <mark>yes</mark>
	* Execute during ramping: <mark>no</mark>
	* Category: <mark>Aircon</mark> (optional)
	* Select "Save"
	* Paste the contents of the file eventscript_izone.lua into the code editor.
	* Select "Save and close"

### 4/ Install the resident script
* Select "Resident"
* Select "Add new script"
	* Script name: <mark>iZone Resident Script</mark>
	* SLeep interval (seconds): <mark>5</mark>
	* Active: <mark>yes</mark>
	* Category: <mark>Aircon</mark> (optional)
	* Select "Save"
	* Paste the contents of the file residentscript_izone.lua into the code editor.
	* Select "Save and close"





## Version History

Feb 2018 initial version
Nov 2020 updated
Mar 2022 transferred to github


