import json,subprocess,sys
m=json.load(open('regions.json'))
px0,py0,px1,py1=m['phone_bbox']; wx0,wy0,wx1,wy1=m['watch_bbox']
pw,ph=px1-px0,py1-py0; ww,wh=wx1-wx0,wy1-wy0
ios,watch,out=sys.argv[1],sys.argv[2],sys.argv[3]
dur=sys.argv[4] if len(sys.argv)>4 else '20'
fc=(f"[1:v]scale={pw}:{ph},format=yuva420p[pv];[3:v]format=gray[pa];[pv][pa]alphamerge[pva];"
    f"[2:v]scale={ww}:{wh},format=yuva420p[wv];[4:v]format=gray[wa];[wv][wa]alphamerge[wva];"
    f"[0:v]format=yuva420p[bg];[bg][pva]overlay={px0}:{py0}[t1];"
    f"[t1][wva]overlay={wx0}:{wy0},format=yuv420p[out]")
subprocess.run(['ffmpeg','-y','-loglevel','error','-loop','1','-t',dur,'-i','poster_despill.png',
 '-i',ios,'-i',watch,'-loop','1','-t',dur,'-i','phone_mask_crop.png','-loop','1','-t',dur,'-i','watch_mask_crop.png',
 '-filter_complex',fc,'-map','[out]','-r','30','-c:v','libx264','-pix_fmt','yuv420p','-crf','18','-shortest','-movflags','+faststart',out],check=True)
print('wrote',out)
