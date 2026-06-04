import json, time, urllib.request, urllib.error, os, glob

SERVER="http://127.0.0.1:8188"
wf = {
 "1":{"class_type":"UNETLoader","inputs":{"unet_name":"qwen_image_2512_fp8_e4m3fn.safetensors","weight_dtype":"default"}},
 "2":{"class_type":"CLIPLoader","inputs":{"clip_name":"qwen_2.5_vl_7b_fp8_scaled.safetensors","type":"qwen_image","device":"default"}},
 "3":{"class_type":"VAELoader","inputs":{"vae_name":"qwen_image_vae.safetensors"}},
 "4":{"class_type":"CLIPTextEncode","inputs":{"clip":["2",0],"text":"masterpiece, best quality, anime style, 1girl, silver hair, holding a katana, detailed hands, five fingers, dynamic pose, cherry blossoms"}},
 "5":{"class_type":"CLIPTextEncode","inputs":{"clip":["2",0],"text":"lowres, bad hands, bad anatomy, extra fingers, fused fingers, missing fingers, worst quality"}},
 "6":{"class_type":"EmptySD3LatentImage","inputs":{"width":1024,"height":1024,"batch_size":1}},
 "7":{"class_type":"KSampler","inputs":{"model":["1",0],"positive":["4",0],"negative":["5",0],"latent_image":["6",0],"seed":12345,"steps":20,"cfg":3.0,"sampler_name":"euler","scheduler":"simple","denoise":1.0}},
 "8":{"class_type":"VAEDecode","inputs":{"samples":["7",0],"vae":["3",0]}},
 "9":{"class_type":"SaveImage","inputs":{"images":["8",0],"filename_prefix":"qwen2512_test"}},
}
data=json.dumps({"prompt":wf}).encode()
try:
    r=urllib.request.urlopen(urllib.request.Request(SERVER+"/prompt",data=data,headers={"Content-Type":"application/json"}),timeout=30)
    pid=json.load(r)["prompt_id"]
    print("SUBMITTED prompt_id",pid,flush=True)
except urllib.error.HTTPError as e:
    print("SUBMIT_ERROR",e.code,e.read().decode()[:800]); raise SystemExit(1)

t0=time.time()
while time.time()-t0 < 300:
    try:
        h=json.load(urllib.request.urlopen(SERVER+"/history/"+pid,timeout=15))
    except Exception as ex:
        time.sleep(2); continue
    if pid in h:
        st=h[pid].get("status",{})
        if h[pid].get("outputs"):
            imgs=[]
            for n,o in h[pid]["outputs"].items():
                for im in o.get("images",[]):
                    imgs.append(im)
            print("DONE in %.1fs"%(time.time()-t0),"status:",st.get("status_str"),"images:",imgs,flush=True)
            break
        if st.get("status_str")=="error":
            print("EXEC_ERROR",json.dumps(h[pid].get("status"))[:800]); raise SystemExit(2)
    time.sleep(3)
else:
    print("TIMEOUT waiting for generation"); raise SystemExit(3)

# verify file on disk
fs=sorted(glob.glob(os.path.expanduser("~/ComfyUI/output/qwen2512_test*.png")),key=os.path.getmtime)
if fs:
    print("IMAGE_FILE",fs[-1],os.path.getsize(fs[-1]),"bytes")
else:
    print("NO_IMAGE_FILE_FOUND")
