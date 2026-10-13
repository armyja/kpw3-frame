@echo off
rem Start the e-ink frame image server. Keep this window open while the Kindle runs.
rem
rem   --pin frame.jpg : always serve server\images\frame.jpg (one fixed picture)
rem   --rotate 90     : rotate the picture 90 deg clockwise first, for a
rem                     SIDEWAYS-mounted Kindle. If it comes out upside down,
rem                     change 90 to 270.
rem   --fit cover     : fill the frame, cropping the edges
rem                     (use "contain" to show the whole picture with margins)
rem
rem To show another picture: put it in server\images\ and change the --pin name,
rem or drop --pin/--rotate to just rotate through every image in the folder.
rem
cd /d "%~dp0"
".venv\Scripts\python.exe" "server\frame_server.py" --port 8000 --rotate 90 --fit cover --pin frame.jpg
pause
