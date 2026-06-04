import json, os

def node(_id, typ, pos, widgets, inputs=None, outputs=None, size=(330,140)):
    return {
        "id":_id,"type":typ,"pos":list(pos),"size":list(size),
        "flags":{},"order":_id-1,"mode":0,
        "inputs":inputs or [], "outputs":outputs or [],
        "properties":{"Node name for S&R":typ},
        "widgets_values":widgets,
    }
def out(name,typ,links): return {"name":name,"type":typ,"links":links,"slot_index":0}
def inp(name,typ,link):  return {"name":name,"type":typ,"link":link}

nodes=[
 node(1,"UNETLoader",(40,80),["qwen_image_2512_fp8_e4m3fn.safetensors","default"],
      outputs=[out("MODEL","MODEL",[1])]),
 node(2,"CLIPLoader",(40,260),["qwen_2.5_vl_7b_fp8_scaled.safetensors","qwen_image"],
      outputs=[out("CLIP","CLIP",[2])]),
 node(3,"LoraLoader",(420,80),["qwen_anime_prithiv.safetensors",1.0,1.0],
      inputs=[inp("model","MODEL",1),inp("clip","CLIP",2)],
      outputs=[out("MODEL","MODEL",[3]),out("CLIP","CLIP",[4,5])]),
 node(4,"VAELoader",(40,440),["qwen_image_vae.safetensors"],
      outputs=[out("VAE","VAE",[10])]),
 node(5,"CLIPTextEncode",(800,40),
      ["Qwen Anime, masterpiece, best quality, 1girl, silver hair, intricate kimono, detailed hands, five fingers, cherry blossoms, dynamic pose, soft lighting"],
      inputs=[inp("clip","CLIP",4)], outputs=[out("CONDITIONING","CONDITIONING",[6])], size=(400,180)),
 node(6,"CLIPTextEncode",(800,260),
      ["lowres, bad hands, bad anatomy, extra fingers, fused fingers, missing fingers, deformed, worst quality, blurry"],
      inputs=[inp("clip","CLIP",5)], outputs=[out("CONDITIONING","CONDITIONING",[7])], size=(400,160)),
 node(7,"EmptySD3LatentImage",(800,460),[1024,1024,1],
      outputs=[out("LATENT","LATENT",[8])]),
 node(8,"KSampler",(1250,80),[777,"randomize",20,3.0,"euler","simple",1.0],
      inputs=[inp("model","MODEL",3),inp("positive","CONDITIONING",6),
              inp("negative","CONDITIONING",7),inp("latent_image","LATENT",8)],
      outputs=[out("LATENT","LATENT",[9])], size=(320,470)),
 node(9,"VAEDecode",(1600,80),[],
      inputs=[inp("samples","LATENT",9),inp("vae","VAE",10)],
      outputs=[out("IMAGE","IMAGE",[11])], size=(210,46)),
 node(10,"SaveImage",(1600,200),["qwen2512_anime"],
      inputs=[inp("images","IMAGE",11)], size=(420,460)),
]
links=[
 [1,1,0,3,0,"MODEL"],
 [2,2,0,3,1,"CLIP"],
 [3,3,0,8,0,"MODEL"],
 [4,3,1,5,0,"CLIP"],
 [5,3,1,6,0,"CLIP"],
 [6,5,0,8,1,"CONDITIONING"],
 [7,6,0,8,2,"CONDITIONING"],
 [8,7,0,8,3,"LATENT"],
 [9,8,0,9,0,"LATENT"],
 [10,4,0,9,1,"VAE"],
 [11,9,0,10,0,"IMAGE"],
]
wf={"last_node_id":10,"last_link_id":11,"nodes":nodes,"links":links,
    "groups":[],"config":{},"extra":{},"version":0.4}
p=os.path.expanduser("~/ComfyUI/user/default/workflows/Qwen2512-Anime-LoRA.json")
open(p,"w").write(json.dumps(wf,indent=2))
print("wrote",p,os.path.getsize(p),"bytes")
print("json valid:",bool(json.load(open(p))))
