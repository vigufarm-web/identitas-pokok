import {test} from 'node:test';
import assert from 'node:assert/strict';
import {QRCodeWriter,QRCodeReader,BarcodeFormat,RGBLuminanceSource,HybridBinarizer,BinaryBitmap} from '@zxing/library';
import {makeCode} from '../src/core.js';
test('QR barcode dapat dibaca kembali dengan isi yang sama',()=>{
 const value=makeCode('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',200000);
 const matrix=new QRCodeWriter().encode(value,BarcodeFormat.QR_CODE,220,220,new Map());
 const pixels=new Uint8ClampedArray(220*220);
 for(let y=0;y<220;y++)for(let x=0;x<220;x++)pixels[y*220+x]=matrix.get(x,y)?0:255;
 const decoded=new QRCodeReader().decode(new BinaryBitmap(new HybridBinarizer(new RGBLuminanceSource(pixels,220,220))));
 assert.equal(decoded.getText(),value);
});
