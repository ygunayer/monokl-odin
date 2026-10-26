ffmpeg -i icon512.png -i icon256.png -i icon128.png -i icon64.png -i icon32.png -filter_complex "[0:v][1:v][2:v][3:v][4:v]concat=n=5:v=1:a=0[outv]" -map "[outv]" icon.ico
