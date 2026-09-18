(function () {
  'use strict';

  var state = {
    page: 'overview',
    containers: [],
    images: [],
    volumes: [],
    containerFilter: 'all'
  };
  var pageOrder = ['overview', 'containers', 'images', 'volumes'];
  var toastTimer = null;

  function byId(id) { return document.getElementById(id); }
  function escapeHtml(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
  function formatBytes(value) {
    var bytes = Number(value || 0);
    if (!isFinite(bytes) || bytes <= 0) return '0 B';
    var units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
    return (bytes / Math.pow(1024, index)).toFixed(index ? 1 : 0) + ' ' + units[index];
  }
  function formatDate(value) {
    if (!value) return '—';
    var date = new Date(value);
    if (isNaN(date.getTime())) return value;
    return date.toLocaleString('zh-CN', { hour12: false });
  }
  function lines(value) {
    return String(value || '').split(/\r?\n/).map(function (line) { return line.trim(); }).filter(Boolean);
  }
  function showToast(message, error) {
    var toast = byId('toast');
    toast.textContent = message;
    toast.className = 'toast show' + (error ? ' error' : '');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toast.className = 'toast'; }, 2800);
  }
  function setBusy(active, text) {
    byId('busy').hidden = !active;
    if (text) byId('busyText').textContent = text;
  }

  function api(action, payload) {
    return window.XiaomiPluginClient.request({
      plugin: 'dockermanager',
      cgi: 'dockermanager.cgi',
      action: action,
      options: {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
        body: JSON.stringify(payload || {}),
        cache: 'no-store',
        credentials: 'same-origin'
      }
    }).then(function (response) {
      return response.text().then(function (text) {
        var data;
        try { data = JSON.parse(text); } catch (error) { throw new Error('设备返回了无法解析的数据'); }
        if (!data.ok) throw new Error(data.error || '操作失败');
        if (data.pluginVersion) byId('pluginVersion').textContent = '插件版本 ' + data.pluginVersion;
        return data;
      });
    });
  }

  function switchPage(page) {
    if (pageOrder.indexOf(page) < 0) return;
    state.page = page;
    document.querySelectorAll('.tab').forEach(function (tab) {
      tab.classList.toggle('active', tab.getAttribute('data-page') === page);
    });
    document.querySelectorAll('.page').forEach(function (section) {
      section.classList.toggle('active', section.id === 'page-' + page);
    });
    if (page === 'overview') loadOverview();
    if (page === 'containers') loadContainers();
    if (page === 'images') loadImages();
    if (page === 'volumes') loadVolumes();
  }

  function detailItem(label, value) {
    return '<div class="detail-item"><span>' + escapeHtml(label) + '</span><strong title="' + escapeHtml(value) + '">' + escapeHtml(value) + '</strong></div>';
  }

  function loadOverview() {
    byId('engineSubtitle').textContent = '正在读取设备信息…';
    return Promise.all([api('system_summary'), api('volume_list')]).then(function (results) {
      var data = results[0];
      state.volumes = results[1].volumes || [];
      byId('engineBadge').className = 'status-pill running';
      byId('engineBadge').innerHTML = '<i></i>运行正常';
      byId('engineSubtitle').textContent = (data.name || '小米智能存储') + ' · Docker ' + (data.serverVersion || '未知版本');
      byId('runningMetric').textContent = data.running;
      byId('stoppedMetric').textContent = data.stopped;
      byId('imageMetric').textContent = data.images;
      byId('volumeMetric').textContent = state.volumes.length;
      byId('systemInfo').className = 'detail-list';
      byId('systemInfo').innerHTML = [
        detailItem('Docker 版本', data.serverVersion || '—'),
        detailItem('主机名', data.name || '—'),
        detailItem('系统', data.operatingSystem || '—'),
        detailItem('架构', data.architecture || '—'),
        detailItem('CPU', String(data.cpus || 0) + ' 核'),
        detailItem('内存', formatBytes(data.memory)),
        detailItem('容器总数', String(data.containers || 0)),
        detailItem('Docker 数据目录', data.dockerRootDir || '—')
      ].join('');
      renderDisk(data.disk || []);
    }).catch(function (error) {
      byId('engineBadge').className = 'status-pill stopped';
      byId('engineBadge').innerHTML = '<i></i>连接失败';
      byId('engineSubtitle').textContent = error.message;
      byId('systemInfo').className = 'empty-state';
      byId('systemInfo').textContent = error.message;
      showToast(error.message, true);
    });
  }

  function diskValue(row, names) {
    for (var i = 0; i < names.length; i += 1) {
      if (row[names[i]] != null) return row[names[i]];
    }
    return '—';
  }
  function renderDisk(rows) {
    var container = byId('diskUsage');
    if (!rows.length) {
      container.className = 'empty-state';
      container.textContent = '当前 Docker 版本未返回空间汇总。';
      return;
    }
    container.className = 'stack';
    container.innerHTML = rows.map(function (row) {
      var type = diskValue(row, ['Type', 'type']);
      var total = diskValue(row, ['TotalCount', 'Total', 'totalCount']);
      var size = diskValue(row, ['Size', 'size']);
      var reclaim = diskValue(row, ['Reclaimable', 'reclaimable']);
      return '<div class="resource-card"><div class="resource-head"><div class="resource-title"><h3>' + escapeHtml(type) + '</h3><p>' + escapeHtml(total) + ' 项</p></div><span class="badge">' + escapeHtml(size) + '</span></div><div class="resource-meta"><span class="meta-chip">可回收 ' + escapeHtml(reclaim) + '</span></div></div>';
    }).join('');
  }

  function containerStateLabel(container) {
    if (container.paused) return '已暂停';
    var labels = { running: '运行中', exited: '已停止', created: '已创建', restarting: '重启中', dead: '异常' };
    return labels[container.state] || container.state || '未知';
  }
  function formatPorts(ports) {
    var values = [];
    Object.keys(ports || {}).forEach(function (containerPort) {
      var bindings = ports[containerPort];
      if (!bindings || !bindings.length) values.push(containerPort);
      else bindings.forEach(function (binding) { values.push((binding.HostIp && binding.HostIp !== '0.0.0.0' ? binding.HostIp + ':' : '') + binding.HostPort + '→' + containerPort); });
    });
    return values;
  }
  function renderContainers() {
    var container = byId('containerList');
    var filtered = state.containers.filter(function (item) {
      if (state.containerFilter === 'running') return item.running;
      if (state.containerFilter === 'stopped') return !item.running;
      return true;
    });
    var running = state.containers.filter(function (item) { return item.running; }).length;
    byId('containerSummary').textContent = state.containers.length + ' 个容器 · ' + running + ' 个运行中';
    if (!filtered.length) {
      container.className = 'empty-state';
      container.textContent = state.containers.length ? '当前筛选条件下没有容器。' : '还没有容器，可以点击右上角创建。';
      return;
    }
    container.className = 'stack';
    container.innerHTML = filtered.map(function (item) {
      var chips = ['ID ' + item.id, '镜像 ' + item.image];
      formatPorts(item.ports).forEach(function (port) { chips.push(port); });
      (item.networks || []).forEach(function (network) { chips.push(network.name + (network.ip ? ' · ' + network.ip : '')); });
      var actions = [];
      if (item.paused) actions.push('<button class="action-button" data-container-op="unpause" data-target="' + escapeHtml(item.id) + '">继续</button>');
      else if (item.running) {
        actions.push('<button class="action-button" data-container-op="stop" data-target="' + escapeHtml(item.id) + '">停止</button>');
        actions.push('<button class="action-button" data-container-op="restart" data-target="' + escapeHtml(item.id) + '">重启</button>');
        actions.push('<button class="action-button" data-container-op="pause" data-target="' + escapeHtml(item.id) + '">暂停</button>');
      } else actions.push('<button class="primary-button" data-container-op="start" data-target="' + escapeHtml(item.id) + '">启动</button>');
      actions.push('<button class="action-button" data-container-logs="' + escapeHtml(item.id) + '" data-name="' + escapeHtml(item.name) + '">日志</button>');
      actions.push('<button class="action-button" data-container-inspect="' + escapeHtml(item.id) + '" data-name="' + escapeHtml(item.name) + '">详情</button>');
      actions.push('<button class="danger-button" data-container-remove="' + escapeHtml(item.id) + '" data-name="' + escapeHtml(item.name) + '" data-running="' + item.running + '">删除</button>');
      return '<article class="resource-card"><div class="resource-head"><div class="resource-title"><h3>' + escapeHtml(item.name || item.id) + '</h3><p>' + escapeHtml(item.image) + '</p></div><span class="badge ' + escapeHtml(item.state) + (item.paused ? ' paused' : '') + '">' + escapeHtml(containerStateLabel(item)) + '</span></div><div class="resource-meta">' + chips.map(function (chip) { return '<span class="meta-chip">' + escapeHtml(chip) + '</span>'; }).join('') + '</div><div class="resource-actions">' + actions.join('') + '</div></article>';
    }).join('');
  }
  function loadContainers() {
    return api('container_list').then(function (data) {
      state.containers = data.containers || [];
      renderContainers();
    }).catch(function (error) {
      byId('containerList').className = 'empty-state'; byId('containerList').textContent = error.message; showToast(error.message, true);
    });
  }
  function runContainerAction(target, operation) {
    setBusy(true, '正在执行容器操作…');
    api('container_action', { target: target, operation: operation }).then(function (data) {
      showToast(data.message || '操作完成'); return loadContainers();
    }).catch(function (error) { showToast(error.message, true); }).finally(function () { setBusy(false); });
  }
  function removeContainer(button) {
    var name = button.getAttribute('data-name');
    var running = button.getAttribute('data-running') === 'true';
    if (!window.confirm('确定删除容器“' + name + '”吗？\n不会自动删除镜像和命名存储卷。')) return;
    setBusy(true, '正在删除容器…');
    api('container_action', { target: button.getAttribute('data-container-remove'), operation: 'remove', force: running, volumes: false }).then(function () {
      showToast('容器已删除'); return loadContainers();
    }).catch(function (error) { showToast(error.message, true); }).finally(function () { setBusy(false); });
  }

  function showTextModal(title, subtitle, content) {
    byId('textModalTitle').textContent = title;
    byId('textModalSubtitle').textContent = subtitle || '';
    byId('textModalContent').textContent = content || '';
    openModal('textModal');
  }
  function loadLogs(target, name) {
    setBusy(true, '正在读取日志…');
    api('container_logs', { target: target, tail: 300 }).then(function (data) {
      showTextModal(name + ' 日志', '最近 ' + data.tail + ' 行', data.logs || '没有日志输出');
    }).catch(function (error) { showToast(error.message, true); }).finally(function () { setBusy(false); });
  }
  function inspectContainer(target, name) {
    setBusy(true, '正在读取容器详情…');
    api('container_inspect', { target: target }).then(function (data) {
      showTextModal(name + ' 详情', '运行、网络、端口和挂载信息', JSON.stringify(data.container, null, 2));
    }).catch(function (error) { showToast(error.message, true); }).finally(function () { setBusy(false); });
  }

  function loadImages() {
    return api('image_list').then(function (data) {
      state.images = data.images || [];
      renderImages();
    }).catch(function (error) { byId('imageList').className = 'empty-state'; byId('imageList').textContent = error.message; showToast(error.message, true); });
  }
  function renderImages() {
    var container = byId('imageList');
    byId('imageSummary').textContent = state.images.length + ' 个本地镜像';
    if (!state.images.length) { container.className = 'empty-state'; container.textContent = '还没有镜像，可在上方输入名称拉取。'; return; }
    container.className = 'stack';
    container.innerHTML = state.images.map(function (item) {
      var title = item.tags.length ? item.tags[0] : '<none>:<none>';
      var extra = item.tags.slice(1);
      return '<article class="resource-card"><div class="resource-head"><div class="resource-title"><h3>' + escapeHtml(title) + '</h3><p>' + escapeHtml(item.id) + ' · ' + escapeHtml(formatDate(item.created)) + '</p></div><span class="badge">' + escapeHtml(formatBytes(item.size)) + '</span></div><div class="resource-meta"><span class="meta-chip">' + escapeHtml(item.os + '/' + item.architecture) + '</span>' + extra.map(function (tag) { return '<span class="meta-chip">' + escapeHtml(tag) + '</span>'; }).join('') + '</div><div class="resource-actions"><button class="danger-button" data-image-remove="' + escapeHtml(item.fullId) + '" data-name="' + escapeHtml(title) + '">删除镜像</button></div></article>';
    }).join('');
  }
  function pullImage() {
    var image = byId('pullImage').value.trim();
    if (!image) return showToast('请输入镜像名称', true);
    setBusy(true, '正在拉取镜像，这可能需要几分钟…');
    api('image_pull', { image: image }).then(function (data) {
      byId('pullImage').value = ''; showToast(data.message || '镜像拉取完成'); return loadImages();
    }).catch(function (error) { showToast(error.message, true); }).finally(function () { setBusy(false); });
  }
  function removeImage(button) {
    if (!window.confirm('确定删除镜像“' + button.getAttribute('data-name') + '”吗？\n正在被容器使用的镜像不会被删除。')) return;
    setBusy(true, '正在删除镜像…');
    api('image_remove', { target: button.getAttribute('data-image-remove'), force: false }).then(function () {
      showToast('镜像已删除'); return loadImages();
    }).catch(function (error) { showToast(error.message, true); }).finally(function () { setBusy(false); });
  }

  function loadVolumes() {
    return api('volume_list').then(function (data) {
      state.volumes = data.volumes || []; renderVolumes();
    }).catch(function (error) { byId('volumeList').className = 'empty-state'; byId('volumeList').textContent = error.message; showToast(error.message, true); });
  }
  function renderVolumes() {
    var container = byId('volumeList');
    byId('volumeSummary').textContent = state.volumes.length + ' 个存储卷';
    if (!state.volumes.length) { container.className = 'empty-state'; container.textContent = '还没有命名存储卷。'; return; }
    container.className = 'stack';
    container.innerHTML = state.volumes.map(function (item) {
      return '<article class="resource-card"><div class="resource-head"><div class="resource-title"><h3>' + escapeHtml(item.name) + '</h3><p>' + escapeHtml(item.mountpoint || '—') + '</p></div><span class="badge">' + escapeHtml(item.driver) + '</span></div><div class="resource-meta"><span class="meta-chip">创建于 ' + escapeHtml(formatDate(item.created)) + '</span><span class="meta-chip">作用域 ' + escapeHtml(item.scope || 'local') + '</span></div><div class="resource-actions"><button class="danger-button" data-volume-remove="' + escapeHtml(item.name) + '">删除存储卷</button></div></article>';
    }).join('');
  }
  function createVolume() {
    var name = byId('volumeName').value.trim();
    if (!name) return showToast('请输入存储卷名称', true);
    setBusy(true, '正在创建存储卷…');
    api('volume_create', { name: name }).then(function () {
      byId('volumeName').value = ''; showToast('存储卷已创建'); return loadVolumes();
    }).catch(function (error) { showToast(error.message, true); }).finally(function () { setBusy(false); });
  }
  function removeVolume(name) {
    if (!window.confirm('确定删除存储卷“' + name + '”吗？\n其中的数据将无法通过该存储卷恢复。')) return;
    setBusy(true, '正在删除存储卷…');
    api('volume_remove', { target: name, force: false }).then(function () {
      showToast('存储卷已删除'); return loadVolumes();
    }).catch(function (error) { showToast(error.message, true); }).finally(function () { setBusy(false); });
  }

  function openModal(id) {
    byId('modalBackdrop').hidden = false;
    byId(id).hidden = false;
    document.body.style.overflow = 'hidden';
  }
  function closeModals() {
    byId('modalBackdrop').hidden = true;
    document.querySelectorAll('.modal').forEach(function (modal) { modal.hidden = true; });
    document.body.style.overflow = '';
  }
  function openCreateContainer() {
    openModal('createContainerModal');
    api('network_list').then(function (data) {
      var select = byId('containerNetwork');
      select.innerHTML = (data.networks || []).map(function (network) { return '<option value="' + escapeHtml(network.name) + '">' + escapeHtml(network.name + ' · ' + network.driver) + '</option>'; }).join('');
      if (!select.options.length) select.innerHTML = '<option value="bridge">bridge</option>';
    }).catch(function (error) { showToast(error.message, true); });
  }
  function createContainer() {
    var image = byId('containerImage').value.trim();
    if (!image) return showToast('镜像为必填项', true);
    var payload = {
      name: byId('containerName').value.trim(), image: image,
      restartPolicy: byId('restartPolicy').value, network: byId('containerNetwork').value,
      ports: lines(byId('containerPorts').value), volumes: lines(byId('containerVolumes').value),
      env: lines(byId('containerEnv').value), command: byId('containerCommand').value.trim(),
      pull: byId('containerPull').checked, start: byId('containerStart').checked,
      readOnly: byId('containerReadOnly').checked
    };
    setBusy(true, payload.pull ? '正在准备镜像并创建容器…' : '正在创建容器…');
    api('container_create', payload).then(function (data) {
      closeModals(); showToast(data.message || '容器已创建');
      ['containerName', 'containerImage', 'containerPorts', 'containerVolumes', 'containerEnv', 'containerCommand'].forEach(function (id) { byId(id).value = ''; });
      return loadContainers();
    }).catch(function (error) { showToast(error.message, true); }).finally(function () { setBusy(false); });
  }

  document.querySelectorAll('.tab').forEach(function (tab) { tab.addEventListener('click', function () { switchPage(tab.getAttribute('data-page')); }); });
  document.querySelectorAll('[data-go]').forEach(function (button) { button.addEventListener('click', function () { switchPage(button.getAttribute('data-go')); }); });
  document.querySelectorAll('.filter').forEach(function (button) {
    button.addEventListener('click', function () {
      state.containerFilter = button.getAttribute('data-filter');
      document.querySelectorAll('.filter').forEach(function (item) { item.classList.toggle('active', item === button); });
      renderContainers();
    });
  });
  document.querySelectorAll('.close-modal').forEach(function (button) { button.addEventListener('click', closeModals); });
  byId('modalBackdrop').addEventListener('click', closeModals);
  byId('openCreateContainer').addEventListener('click', openCreateContainer);
  byId('createContainerButton').addEventListener('click', createContainer);
  byId('pullImageButton').addEventListener('click', pullImage);
  byId('createVolumeButton').addEventListener('click', createVolume);
  byId('refreshButton').addEventListener('click', function () { switchPage(state.page); });
  byId('pullImage').addEventListener('keydown', function (event) { if (event.key === 'Enter') pullImage(); });
  byId('volumeName').addEventListener('keydown', function (event) { if (event.key === 'Enter') createVolume(); });

  byId('containerList').addEventListener('click', function (event) {
    var button = event.target.closest('button'); if (!button) return;
    if (button.hasAttribute('data-container-op')) runContainerAction(button.getAttribute('data-target'), button.getAttribute('data-container-op'));
    if (button.hasAttribute('data-container-remove')) removeContainer(button);
    if (button.hasAttribute('data-container-logs')) loadLogs(button.getAttribute('data-container-logs'), button.getAttribute('data-name'));
    if (button.hasAttribute('data-container-inspect')) inspectContainer(button.getAttribute('data-container-inspect'), button.getAttribute('data-name'));
  });
  byId('imageList').addEventListener('click', function (event) { var button = event.target.closest('[data-image-remove]'); if (button) removeImage(button); });
  byId('volumeList').addEventListener('click', function (event) { var button = event.target.closest('[data-volume-remove]'); if (button) removeVolume(button.getAttribute('data-volume-remove')); });

  var swipeStart = null;
  byId('shell').addEventListener('touchstart', function (event) {
    if (!byId('modalBackdrop').hidden || event.touches.length !== 1) return;
    if (event.target.closest('input,textarea,select,button,pre')) return;
    swipeStart = { x: event.touches[0].clientX, y: event.touches[0].clientY };
  }, { passive: true });
  byId('shell').addEventListener('touchend', function (event) {
    if (!swipeStart || !event.changedTouches.length) return;
    var dx = event.changedTouches[0].clientX - swipeStart.x;
    var dy = event.changedTouches[0].clientY - swipeStart.y;
    swipeStart = null;
    if (Math.abs(dx) < 65 || Math.abs(dx) < Math.abs(dy) * 1.35) return;
    var index = pageOrder.indexOf(state.page);
    if (dx < 0 && index < pageOrder.length - 1) switchPage(pageOrder[index + 1]);
    if (dx > 0 && index > 0) switchPage(pageOrder[index - 1]);
  }, { passive: true });

  loadOverview();
}());
