import json, time, urllib.request, urllib.error, os, glob, sys
SERVER="http://127.0.0.1:8188"
LORA=sys.argv[1] if len(sys.argv)>1 else "qwen_anime_prithiv.safetensors"
TRIG=sys.argv[2] if len(sys.argv)>2 else "Qwen Anime"
PREFIX=sys.argv[3] if len(sys.argv)>3 else "qwen_lora_test"
wf = {
 "1":{"class_type":"UNETLoader","inputs":{"unet_name":"qwen_image_2512_fp8_e4m3fn.safetensors","weight_dtype":"default"}},
 "2":{"class_type":"CLIPLoader","inputs":{"clip_name":"qwen_2.5_vl_7b_fp8_scaled.safetensors","type":"qwen_image","device":"default"}},
 "10":{"class_type":"LoraLoader","inputs":{"model":["1",0],"clip":["2",0],"lora_name":LORA,"strength_model":1.0,"strength_clip":1.0}},
 "3":{"class_type":"VAELoader","inputs":{"vae_name":"qwen_image_vae.safetensors"}},
 "4":{"class_type":"CLIPTextEncode","inputs":{"clip":["10",1],"text":TRIG+", masterpiece, best quality, 1girl, silver hair, holding a katana, detailed hands, five fingers, cherry blossoms, dynamic pose"}},
 "5":{"class_type":"CLIPTextEncode","inputs":{"clip":["10",1],"text":"lowres, bad hands, bad anatomy, extra fingers, fused fingers, missing fingers, worst quality"}},
 "6":{"class_type":"EmptySD3LatentImage","inputs":{"width":1024,"height":1024,"batch_size":1}},
 "7":{"class_type":"KSampler","inputs":{"model":["10",0],"positive":["4",0],"negative":["5",0],"latent_image":["6",0],"seed":777,"steps":20,"cfg":3.0,"sampler_name":"euler","scheduler":"simple","denoise":1.0}},
 "8":{"class_type":"VAEDecode","inputs":{"samples":["7",0],"vae":["3",0]}},
 "9":{"class_type":"SaveImage","inputs":{"images":["8",0],"filename_prefix":PREFIX}},
}
data=json.dumps({"prompt":wf}).encode()
try:
    r=urllib.request.urlopen(urllib.request.Request(SERVER+"/prompt",data=data,headers={"Content-Type":"application/json"}),timeout=30)
    pid=json.load(r)["prompt_id"]; print("SUBMITTED",pid,"lora",LORA,flush=True)
except urllib.error.HTTPError as e:
    print("SUBMIT_ERROR",e.code,e.read().decode()[:1000]); raise SystemExit(1)
t0=time.time()
while time.time()-t0<300:
    try: h=json.load(urllib.request.urlopen(SERVER+"/history/"+pid,timeout=15))
    except Exception: time.sleep(2); continue
    if pid in h:
        st=h[pid].get("status",{})
        if h[pid].get("outputs"):
            imgs=[im for o in h[pid]["outputs"].values() for im in o.get("images",[])]
            print("DONE %.1fs"%(time.time()-t0),st.get("status_str"),imgs,flush=True); break
        if st.get("status_str")=="error":
            print("EXEC_ERROR",json.dumps(st)[:1000]); raise SystemExit(2)
    time.sleep(3)
else:
    print("TIMEOUT"); raise SystemExit(3)
fs=sorted(glob.glob(os.path.expanduser("~/ComfyUI/output/"+PREFIX+"*.png")),key=os.path.getmtime)
print("IMAGE", (fs[-1]+" "+str(os.path.getsize(fs[-1]))) if fs else "NONE")
