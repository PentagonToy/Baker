"""ONNX inference for the exported, end-to-end DocLayout-YOLO checkpoint."""
import ast
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort


class Layout:
    def __init__(self,path):
        ort.disable_telemetry_events();options=ort.SessionOptions();options.intra_op_num_threads=2;options.inter_op_num_threads=1
        options.enable_cpu_mem_arena=False;options.enable_mem_pattern=False
        self.session=ort.InferenceSession(str(path),sess_options=options,providers=['CPUExecutionProvider'])
        self.names=ast.literal_eval(self.session.get_modelmeta().custom_metadata_map['names'])

    def predict(self,image):
        width,height=image.size;scale=min(1024/width,1024/height);w,h=round(width*scale),round(height*scale)
        left=round((1024-w)/2-.1);top=round((1024-h)/2-.1)
        resized=cv2.resize(np.asarray(image),(w,h),interpolation=cv2.INTER_LINEAR)
        padded=np.full((1024,1024,3),114,dtype=np.uint8);padded[top:top+h,left:left+w]=resized
        tensor=np.ascontiguousarray(padded.transpose(2,0,1)[None],dtype=np.float32)/255
        predictions=self.session.run(None,{'images':tensor})[0][0];boxes=[]
        for x1,y1,x2,y2,score,kind in predictions:
            if score<.2:continue
            box=[max(0,float((x1-left)/scale)),max(0,float((y1-top)/scale)),min(width,float((x2-left)/scale)),min(height,float((y2-top)/scale))]
            if box[2]<=box[0] or box[3]<=box[1]:continue
            boxes.append({'box':box,'class':self.names[int(kind)],'score':float(score)})
        unique=[]
        for box in sorted(boxes,key=lambda value:value['score'],reverse=True):
            a=box['box'];duplicate=False
            for previous in unique:
                if previous['class']!=box['class']:continue
                b=previous['box'];intersection=max(0,min(a[2],b[2])-max(a[0],b[0]))*max(0,min(a[3],b[3])-max(a[1],b[1]))
                union=(a[2]-a[0])*(a[3]-a[1])+(b[2]-b[0])*(b[3]-b[1])-intersection
                if intersection/max(union,1)>.9:duplicate=True;break
            if not duplicate:unique.append(box)
        return unique
