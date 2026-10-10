const fs=require('fs'),path=require('path'),assert=require('assert/strict'),{chromium}=require('playwright');
const ui=path.resolve(__dirname,'../payload/ui');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.EDGE_PATH});
 try{for(const [name,width,height,mobile,dark] of [['desktop',1440,900,false,false],['small',800,600,false,false],['ios',390,844,true,false],['ios-dark',390,844,true,true],['android',360,740,true,false],['android-dark',360,740,true,true]]){
  const context=await browser.newContext({viewport:{width,height},isMobile:mobile,hasTouch:mobile,colorScheme:dark?'dark':'light',userAgent:mobile?(name.startsWith('ios')?'Mozilla/5.0 iPhone Mobile Safari':'Mozilla/5.0 Android Mobile Chrome'):'SmartStorage Electron/30'});
  const page=await context.newPage(),calls=[],errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.exposeFunction('imageMock',q=>{
   calls.push(q.action);
   if(q.action==='system_summary')return {ok:true,engineRunning:true,images:9};
   if(q.action==='volume_list')return {ok:true,volumes:[]};
   const all=JSON.parse(q.options.body).includeIntermediate;
   return {ok:true,images:Array.from({length:all?14:9},(_,i)=>({id:'img'+i,fullId:'sha256:img'+i,tags:i<8?['example/image:'+i]:[],intermediate:i>=9,os:'linux',architecture:'arm64',size:1024,created:'2026-10-01'}))};
  });
  await page.route('**/*',r=>{const file=path.basename(new URL(r.request().url()).pathname)||'index.html';if(!/^(index\.html|[\w-]+\.(js|css))$/.test(file)||!fs.existsSync(path.join(ui,file)))return r.abort();let body=fs.readFileSync(path.join(ui,file),'utf8');if(file==='client-bridge.js')body+='\nwindow.XiaomiPluginClient.request=async q=>new Response(JSON.stringify(await window.imageMock(q)));';return r.fulfill({body,contentType:file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':'text/html'});});
  await page.goto('http://images.test/index.html');const root=page.locator('[data-minas-plugin="dockermanager"]');
  await page.waitForFunction(()=>document.querySelector('#imageMetric').textContent==='9');
  await root.locator('.tab[data-page="images"]').click();
  await page.waitForFunction(()=>document.querySelectorAll('#imageList .resource-card').length===9);
  const toggle=root.locator('#showIntermediateImages');assert(!await toggle.isChecked());
  await toggle.check();await page.waitForFunction(()=>document.querySelectorAll('#imageList .resource-card').length===14);
  assert((await root.locator('#imageSummary').innerText()).includes('9 个普通镜像 · 5 个构建中间镜像'));
  assert.equal(await root.locator('#imageList h3').filter({hasText:'构建中间镜像'}).count(),5);
  assert(await root.locator('#page-images').evaluate(e=>e.scrollWidth<=e.clientWidth+1));
  if(process.env.IMAGE_SCREENSHOTS){fs.mkdirSync(process.env.IMAGE_SCREENSHOTS,{recursive:true});await page.screenshot({path:path.join(process.env.IMAGE_SCREENSHOTS,name+'.png')});}
  await toggle.uncheck();await page.waitForFunction(()=>document.querySelectorAll('#imageList .resource-card').length===9);
  assert(calls.every(a=>['system_summary','volume_list','image_list'].includes(a)));
  assert.deepEqual(errors,[]);console.log(name+': passed');await context.close();
 }}finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
