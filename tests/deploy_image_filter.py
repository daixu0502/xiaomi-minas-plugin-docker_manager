"""Targeted v1.1.3 update. Refuses busy/shared-component drift; no Docker mutations."""
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from contextlib import ExitStack
from pathlib import Path

BASELINES = {
    'common/docker-manager-helper':'e662e331ddd9de95b64ef7bd5af39c73a45f222dd1389389d11fce0e3d9f1dd3',
    'common/privileged_runtime.py':'589acf4dc3d70a09bb0e66e76ecba2e8ee8194f7842102bc494d0cc6d0cdc4c4',
    'ui/app.js':'5ef0facf12607f1c29cbeb8240899518c9b84ae6127144ffa614075f9d090f0d',
    'ui/index.html':'131147d8c348915214ba358a31a36b1e53c9bf13776a7aafa702b5e926b1714c',
    'ui/style.css':'22c854037ca9c17347ad9e8ab55de5686cc23aaefce2e342448b871161ddaf18',
    'ui/docker-manager.cgi':'3ec67beb106c45942f6a0aa3f73150a230baa374f2194fa91ec92472328e44b6',
}


def sha(data):return hashlib.sha256(data).hexdigest()


def main(user, payload):
    assert os.geteuid()==0 and re.fullmatch(r'u[0-9]+',user)
    assert os.path.ismount('/nas/pool0')
    home=Path('/home')/user/'plugin/dockermanager'
    source=(home/'src').resolve(strict=True)
    assert source==Path('/nas/pool0')/user/'plugin/pluginsrc/dockermanager'
    common=Path('/data/.minas-privileged')
    sys.path.insert(0,str(common))
    import privileged_runtime as runtime
    import component_admin
    plugin_registry=Path('/data/plugin')/(user+'.list')
    info_path=home/'INFO'
    originals={}
    def replace(path,content):
        assert not path.is_symlink()
        st=path.stat()
        if path not in originals:originals[path]=(path.read_bytes(),st)
        fd,name=tempfile.mkstemp(prefix='.image-filter-',dir=path.parent)
        try:
            with os.fdopen(fd,'wb') as out:
                out.write(content);out.flush();os.fsync(out.fileno())
                os.fchmod(out.fileno(),st.st_mode & 0o777);os.fchown(out.fileno(),st.st_uid,st.st_gid)
            os.replace(name,path)
        finally:
            if os.path.exists(name):os.unlink(name)
    def write_json(path,data):replace(path,(json.dumps(data,ensure_ascii=False,indent=2)+'\n').encode())
    def docker(args):return subprocess.check_output(['/data/docker/docker']+args,timeout=30)
    def pid():return subprocess.check_output(['systemctl','show','docker.service','-p','MainPID','--value'])
    before_pid=pid()
    before_images=set(docker(['image','ls','-aq','--no-trunc']).splitlines())
    before_containers=set(docker(['container','ls','-aq','--no-trunc']).splitlines())
    with ExitStack() as stack:
        for name in ('/data/plugin/.local-plugin-installer.lock','/data/plugin/.'+user+'.plugins.lock'):
            lock=stack.enter_context(open(name,'a'));fcntl.flock(lock,fcntl.LOCK_EX)
        stack.enter_context(runtime.lock('component.lock',exclusive=True,wait=3))
        component_admin.check_idle()
        info=json.loads(info_path.read_bytes());assert info['version']=='1.1.2'
        registry=runtime.registry();assert registry['version']=='1.0.0'
        changes={}
        for relative,expected in BASELINES.items():
            target=common/Path(relative).name if relative.startswith('common/') else source/relative
            assert not target.is_symlink() and sha(target.read_bytes().replace(b'\r\n',b'\n'))==expected, relative+' has unexpected changes'
            changes[target]=(payload/relative).read_bytes().replace(b'\r\n',b'\n')
        try:
            for target,data in changes.items():replace(target,data)
            registry['version']='1.0.1';registry['modules']['dockermanager']='1.1.3'
            write_json(common/'registry.json',registry)
            files=sorted(p for p in source.rglob('*') if p.is_file() and not p.is_symlink())
            info.update(version='1.1.3',timestamp=int(time.time()),changelog='默认隐藏构建中间镜像，新增显示开关，首页数量按普通镜像统计',
                        abstract=sha(''.join(sha(p.read_bytes())+'\n' for p in files).encode()),size=sum(p.stat().st_blocks*512 for p in files))
            write_json(info_path,info)
            plugins=json.loads(plugin_registry.read_bytes())
            plugins['dockermanager']['info']={k:v for k,v in info.items() if k!='abstract'}
            plugins['dockermanager']['changetime']=info['timestamp'];write_json(plugin_registry,plugins)
            env=dict(os.environ,PLUG_USER=user,PLUG_NAME='dockermanager',PLUG_HOME_DIR=str(home),PLUG_SRC_DIR=str(source),PLUG_TMP_DIR=str((home/'tmp').resolve()),PLUG_STATUS='unverified')
            subprocess.run(['/usr/bin/plugin.sh','verify'],env=env,timeout=30,check=True,capture_output=True)
            assert before_pid==pid()
            assert before_images==set(docker(['image','ls','-aq','--no-trunc']).splitlines())
            assert before_containers==set(docker(['container','ls','-aq','--no-trunc']).splitlines())
        except BaseException:
            for target,(data,st) in reversed(list(originals.items())):replace(target,data)
            raise
    print('PASS deployed 1.1.3 / shared component 1.0.1; Docker PID, images and containers unchanged; no persistent backups')


if __name__=='__main__':main(sys.argv[1],Path(sys.argv[2]))
