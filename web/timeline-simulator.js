/**
 * SleepTimelineSimulator
 * Interactive sleep timeline simulator engine for SleepDaddy web demo.
 * Renders multi-source sleep stage intervals, stepped stage line profiles,
 * supports viewport panning/zooming, hover tooltips, source filtering,
 * and brief awake spike filtering.
 */

class SleepTimelineSimulator {
  constructor(options = {}) {
    // 1. Container & Canvas setup
    if (typeof window !== 'undefined') {
      this.container = typeof options.container === 'string'
        ? document.querySelector(options.container)
        : (options.container || document.querySelector('.simulator-canvas-wrapper'));
    } else {
      this.container = null;
    }

    if (this.container) {
      this.canvas = options.canvas || this.container.querySelector('canvas');
      if (!this.canvas) {
        this.canvas = document.createElement('canvas');
        this.container.appendChild(this.canvas);
      }
      this.ctx = this.canvas.getContext('2d');
    } else {
      this.canvas = null;
      this.ctx = null;
    }

    // 2. Control HUD Bindings (DOM elements)
    if (typeof document !== 'undefined') {
      this.sourceFilterSelect = document.querySelector(options.sourceFilter || '#source-filter');
      this.briefAwakeToggle = document.querySelector(options.briefAwakeToggle || '#brief-awake-toggle');
      this.zoomInBtn = document.querySelector(options.zoomInBtn || '#zoom-in');
      this.zoomOutBtn = document.querySelector(options.zoomOutBtn || '#zoom-out');
      this.resetViewBtn = document.querySelector(options.resetViewBtn || '#reset-view');

      // Stat elements
      this.statTotalEl = document.querySelector(options.statTotal || '#stat-total');
      this.statTotalLabelEl = document.querySelector(options.statTotalLabel || '#stat-total-label');
      this.statDeepEl = document.querySelector(options.statDeep || '#stat-deep');
      this.statRemEl = document.querySelector(options.statRem || '#stat-rem');
      this.statCoreEl = document.querySelector(options.statCore || '#stat-core');
      this.statAwakeEl = document.querySelector(options.statAwake || '#stat-awake');
      this.statAttributionEl = document.querySelector(options.statAttribution || '#stat-source-attribution');
    }

    // 3. Stage & Color definitions
    this.stages = ['awake', 'rem', 'core', 'deep'];
    this.stageLabels = {
      awake: 'Awake',
      rem: 'REM',
      core: 'Core',
      deep: 'Deep'
    };
    this.stageColors = {
      awake: '#fbbf24', // Amber
      rem: '#818cf8',   // Indigo
      core: '#3b82f6',  // Electric Blue
      deep: '#8b5cf6'   // Purple / Violet
    };
    this.stageLevels = {
      awake: 0,
      rem: 1,
      core: 2,
      deep: 3
    };

    // 4. Viewport & Filter state
    this.selectedSource = 'all'; // 'all', 'apple_watch', 'oura'
    this.hideBriefAwake = false;

    // Fixed 9-hour night span (10:15 PM - 7:15 AM)
    const baseDate = new Date();
    baseDate.setHours(22, 15, 0, 0);
    this.nightStart = new Date(baseDate.getTime());
    this.nightEnd = new Date(baseDate.getTime() + 9 * 60 * 60 * 1000);

    this.viewStartTime = this.nightStart.getTime();
    this.viewEndTime = this.nightEnd.getTime();
    this.minViewSpan = 15 * 60 * 1000; // 15 mins
    this.maxViewSpan = 14 * 60 * 60 * 1000; // 14 hours

    // Interactive state
    this.isDragging = false;
    this.dragStartX = 0;
    this.dragStartViewStart = 0;
    this.dragStartViewEnd = 0;
    this.hoveredInterval = null;
    this.mousePos = null;

    // Layout Padding
    this.paddingLeft = 75;
    this.paddingRight = 25;
    this.paddingTop = 30;
    this.paddingBottom = 40;

    // Touch pinch state
    this.initialPinchDistance = null;

    // Performance & RAF state
    this.rafPending = false;
    this.rafId = null;

    // Store listener references for destroy() cleanup
    this._handlers = {};

    // Generate Dataset
    this.dataset = this.generateSyntheticDataset();

    // Init logic if environment supports DOM
    if (this.canvas && this.ctx) {
      this.initTooltip();
      this.bindEvents();
      this.bindHUDControls();
      this.resizeCanvas();
      this.updateStats();
      this.render();
    }
  }

  get activeSource() {
    return this.selectedSource;
  }

  set activeSource(val) {
    this.selectedSource = val;
  }

  generateSyntheticDataset() {
    const start = this.nightStart.getTime();
    const minute = 60 * 1000;

    const createInterval = (offsetMinutes, durationMinutes, stage, source) => {
      const startTime = new Date(start + offsetMinutes * minute);
      const endTime = new Date(start + (offsetMinutes + durationMinutes) * minute);
      return {
        id: `${source}-${offsetMinutes}-${stage}`,
        stage,
        source,
        startTime,
        endTime,
        startTimestamp: startTime.getTime(),
        endTimestamp: endTime.getTime(),
        durationSeconds: durationMinutes * 60
      };
    };

    // Apple Watch dataset
    const appleWatch = [
      createInterval(0, 10, 'awake', 'apple_watch'),
      createInterval(10, 30, 'core', 'apple_watch'),
      createInterval(40, 50, 'deep', 'apple_watch'),
      createInterval(90, 30, 'core', 'apple_watch'),
      createInterval(120, 25, 'rem', 'apple_watch'),
      createInterval(145, 30, 'core', 'apple_watch'),
      createInterval(175, 45, 'deep', 'apple_watch'),
      createInterval(220, 1, 'awake', 'apple_watch'),  // Micro awake 1 (1 min spike)
      createInterval(221, 39, 'core', 'apple_watch'),
      createInterval(260, 40, 'rem', 'apple_watch'),
      createInterval(300, 45, 'core', 'apple_watch'),
      createInterval(345, 30, 'deep', 'apple_watch'),
      createInterval(375, 45, 'rem', 'apple_watch'),
      createInterval(420, 1, 'awake', 'apple_watch'),  // Micro awake 2 (1 min spike)
      createInterval(421, 49, 'core', 'apple_watch'),
      createInterval(470, 50, 'rem', 'apple_watch'),
      createInterval(520, 20, 'awake', 'apple_watch')
    ];

    // Oura Ring dataset (Distinct, realistic Oura sleep architecture)
    const oura = [
      createInterval(0, 8, 'awake', 'oura'),
      createInterval(8, 22, 'core', 'oura'),
      createInterval(30, 65, 'deep', 'oura'),
      createInterval(95, 25, 'core', 'oura'),
      createInterval(120, 35, 'rem', 'oura'),
      createInterval(155, 40, 'core', 'oura'),
      createInterval(195, 35, 'deep', 'oura'),
      createInterval(230, 30, 'core', 'oura'),
      createInterval(260, 50, 'rem', 'oura'),
      createInterval(310, 1, 'awake', 'oura'),         // Micro awake 1 (1 min spike)
      createInterval(311, 44, 'core', 'oura'),
      createInterval(355, 25, 'deep', 'oura'),
      createInterval(380, 55, 'rem', 'oura'),
      createInterval(435, 40, 'core', 'oura'),
      createInterval(475, 45, 'rem', 'oura'),
      createInterval(520, 20, 'awake', 'oura')
    ];

    return [...appleWatch, ...oura];
  }

  getFilteredDataset() {
    if (this.selectedSource === 'apple_watch') {
      return this.dataset.filter(d => d.source === 'apple_watch');
    }
    if (this.selectedSource === 'oura') {
      return this.dataset.filter(d => d.source === 'oura');
    }
    // 'all': return all dataset intervals (both apple_watch and oura)
    return this.dataset;
  }

  getVisibleRenderIntervals() {
    const dataset = this.getFilteredDataset();
    if (!this.hideBriefAwake) {
      return dataset;
    }
    // Brief awake spike filter: hide awake <= 60 seconds (1 minute)
    return dataset.filter(interval => {
      if (interval.stage === 'awake' && interval.durationSeconds <= 60) {
        return false;
      }
      return true;
    });
  }

  getVisibleIntervals() {
    return this.getVisibleRenderIntervals();
  }

  getDatasetBounds() {
    let minTime = this.nightStart ? this.nightStart.getTime() : Infinity;
    let maxTime = this.nightEnd ? this.nightEnd.getTime() : -Infinity;
    if (this.dataset && this.dataset.length > 0) {
      this.dataset.forEach(d => {
        if (d.startTimestamp < minTime) minTime = d.startTimestamp;
        if (d.endTimestamp > maxTime) maxTime = d.endTimestamp;
      });
    }
    const buffer = 15 * 60 * 1000; // 15 minutes buffer
    return {
      minAllowed: minTime - buffer,
      maxAllowed: maxTime + buffer
    };
  }

  clampViewBounds() {
    const { minAllowed, maxAllowed } = this.getDatasetBounds();
    const maxAllowedSpan = maxAllowed - minAllowed;
    let currentSpan = this.viewEndTime - this.viewStartTime;

    if (currentSpan < this.minViewSpan) currentSpan = this.minViewSpan;
    if (currentSpan > maxAllowedSpan) currentSpan = maxAllowedSpan;

    if (this.viewStartTime < minAllowed) {
      this.viewStartTime = minAllowed;
      this.viewEndTime = minAllowed + currentSpan;
    }
    if (this.viewEndTime > maxAllowed) {
      this.viewEndTime = maxAllowed;
      this.viewStartTime = maxAllowed - currentSpan;
      if (this.viewStartTime < minAllowed) {
        this.viewStartTime = minAllowed;
      }
    }
  }

  scheduleRender() {
    if (this.rafPending) return;
    this.rafPending = true;
    if (typeof requestAnimationFrame !== 'undefined') {
      this.rafId = requestAnimationFrame(() => {
        this.rafPending = false;
        this.render();
      });
    } else {
      this.rafPending = false;
      this.render();
    }
  }

  initTooltip() {
    if (!this.container) return;
    let tooltip = this.container.querySelector('#simulator-tooltip');
    if (!tooltip) {
      tooltip = document.createElement('div');
      tooltip.id = 'simulator-tooltip';
      tooltip.style.position = 'absolute';
      tooltip.style.pointerEvents = 'none';
      tooltip.style.background = 'rgba(15, 23, 42, 0.94)';
      tooltip.style.backdropFilter = 'blur(12px)';
      tooltip.style.webkitBackdropFilter = 'blur(12px)';
      tooltip.style.border = '1px solid rgba(129, 140, 248, 0.35)';
      tooltip.style.borderRadius = '8px';
      tooltip.style.padding = '10px 14px';
      tooltip.style.fontSize = '0.85rem';
      tooltip.style.color = '#f8fafc';
      tooltip.style.boxShadow = '0 10px 25px rgba(0, 0, 0, 0.5)';
      tooltip.style.zIndex = '50';
      tooltip.style.display = 'none';
      tooltip.style.whiteSpace = 'nowrap';
      tooltip.style.transition = 'opacity 0.1s ease';
      this.container.appendChild(tooltip);
    }
    this.tooltipEl = tooltip;
  }

  showTooltip(interval, mouseX, mouseY) {
    if (!this.tooltipEl) return;

    const stageLabel = this.stageLabels[interval.stage] || interval.stage;
    const color = this.stageColors[interval.stage] || '#64748b';
    const startTimeStr = this.formatTime(interval.startTime);
    const endTimeStr = this.formatTime(interval.endTime);
    const durationStr = this.formatDuration(interval.durationSeconds);
    const sourceStr = interval.source === 'apple_watch' ? 'Apple Watch' : 'Oura Ring';

    // XSS-Safe DOM construction using textContent
    const header = document.createElement('div');
    header.style.display = 'flex';
    header.style.alignItems = 'center';
    header.style.gap = '6px';
    header.style.fontWeight = '700';
    header.style.marginBottom = '6px';

    const dot = document.createElement('span');
    dot.style.width = '10px';
    dot.style.height = '10px';
    dot.style.borderRadius = '50%';
    dot.style.backgroundColor = color;
    dot.style.boxShadow = `0 0 6px ${color}`;

    const titleSpan = document.createElement('span');
    titleSpan.textContent = `${stageLabel} Sleep`;

    header.appendChild(dot);
    header.appendChild(titleSpan);

    const createRow = (label, value) => {
      const row = document.createElement('div');
      row.style.color = '#94a3b8';
      row.style.fontSize = '0.8rem';
      row.style.marginBottom = '3px';

      const strong = document.createElement('strong');
      strong.style.color = '#e2e8f0';
      strong.textContent = `${label}: `;

      const valText = document.createTextNode(value);

      row.appendChild(strong);
      row.appendChild(valText);
      return row;
    };

    const timeRow = createRow('Time', `${startTimeStr} – ${endTimeStr}`);
    const durationRow = createRow('Duration', durationStr);
    const sourceRow = createRow('Source', sourceStr);

    if (typeof this.tooltipEl.replaceChildren === 'function') {
      this.tooltipEl.replaceChildren(header, timeRow, durationRow, sourceRow);
    } else {
      while (this.tooltipEl.firstChild) {
        this.tooltipEl.removeChild(this.tooltipEl.firstChild);
      }
      this.tooltipEl.appendChild(header);
      this.tooltipEl.appendChild(timeRow);
      this.tooltipEl.appendChild(durationRow);
      this.tooltipEl.appendChild(sourceRow);
    }
    this.tooltipEl.style.display = 'block';

    // Position tooltip near cursor inside container bounds
    const tooltipWidth = this.tooltipEl.offsetWidth || 180;
    const tooltipHeight = this.tooltipEl.offsetHeight || 100;
    let posX = mouseX + 15;
    let posY = mouseY - 15;

    if (posX + tooltipWidth > this.width) {
      posX = mouseX - tooltipWidth - 15;
    }
    if (posY + tooltipHeight > this.height) {
      posY = this.height - tooltipHeight - 10;
    }
    if (posY < 10) posY = 10;

    this.tooltipEl.style.left = `${posX}px`;
    this.tooltipEl.style.top = `${posY}px`;
  }

  formatDuration(totalSeconds) {
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    if (hours > 0) {
      return `${hours}h ${minutes}m`;
    }
    return `${minutes}m`;
  }

  formatTime(date) {
    if (!date) return '';
    let h = date.getHours();
    const m = date.getMinutes();
    const ampm = h >= 12 ? 'PM' : 'AM';
    h = h % 12;
    h = h ? h : 12;
    const mStr = m < 10 ? `0${m}` : m;
    return `${h}:${mStr} ${ampm}`;
  }

  bindHUDControls() {
    this._handlers.onSourceChange = (e) => {
      this.selectedSource = e.target.value;
      this.updateStats();
      this.scheduleRender();
    };

    this._handlers.onBriefAwakeChange = (e) => {
      this.hideBriefAwake = e.target.checked;
      this.scheduleRender();
    };

    this._handlers.onZoomIn = () => {
      this.zoom(0.8);
    };

    this._handlers.onZoomOut = () => {
      this.zoom(1.25);
    };

    this._handlers.onResetView = () => {
      this.resetView();
    };

    if (this.sourceFilterSelect) {
      this.sourceFilterSelect.addEventListener('change', this._handlers.onSourceChange);
    }
    if (this.briefAwakeToggle) {
      this.briefAwakeToggle.addEventListener('change', this._handlers.onBriefAwakeChange);
    }
    if (this.zoomInBtn) {
      this.zoomInBtn.addEventListener('click', this._handlers.onZoomIn);
    }
    if (this.zoomOutBtn) {
      this.zoomOutBtn.addEventListener('click', this._handlers.onZoomOut);
    }
    if (this.resetViewBtn) {
      this.resetViewBtn.addEventListener('click', this._handlers.onResetView);
    }
  }

  bindEvents() {
    if (!this.canvas) return;

    this._handlers.onResize = () => {
      this.resizeCanvas();
      this.scheduleRender();
    };

    this._handlers.onMouseDown = (e) => {
      this.isDragging = true;
      this.dragStartX = e.clientX;
      this.dragStartViewStart = this.viewStartTime;
      this.dragStartViewEnd = this.viewEndTime;
      if (this.container) this.container.style.cursor = 'grabbing';
    };

    this._handlers.onMouseMove = (e) => {
      const rect = this.canvas.getBoundingClientRect();
      const mouseX = e.clientX - rect.left;
      const mouseY = e.clientY - rect.top;

      if (this.isDragging) {
        const plotWidth = this.width - this.paddingLeft - this.paddingRight;
        const deltaX = e.clientX - this.dragStartX;
        const viewSpan = this.dragStartViewEnd - this.dragStartViewStart;
        const deltaTime = (deltaX / plotWidth) * viewSpan;

        this.viewStartTime = this.dragStartViewStart - deltaTime;
        this.viewEndTime = this.dragStartViewEnd - deltaTime;
        this.clampViewBounds();
        this.scheduleRender();
      } else if (mouseX >= 0 && mouseX <= this.width && mouseY >= 0 && mouseY <= this.height) {
        const stateChanged = this.updateHoverState(mouseX, mouseY);
        if (stateChanged) {
          this.scheduleRender();
        }
      }
    };

    this._handlers.onMouseUp = () => {
      if (this.isDragging) {
        this.isDragging = false;
        if (this.container) this.container.style.cursor = 'grab';
      }
    };

    this._handlers.onMouseLeave = () => {
      const changed = this.hoveredInterval !== null || this.mousePos !== null;
      this.mousePos = null;
      this.hoveredInterval = null;
      if (this.tooltipEl) this.tooltipEl.style.display = 'none';
      if (changed) {
        this.scheduleRender();
      }
    };

    this._handlers.onWheel = (e) => {
      e.preventDefault();
      const rect = this.canvas.getBoundingClientRect();
      const mouseX = e.clientX - rect.left;
      const zoomFactor = e.deltaY < 0 ? 0.85 : 1.15;
      this.zoomAt(mouseX, zoomFactor);
    };

    this._handlers.onTouchStart = (e) => {
      if (e.touches.length === 1) {
        this.isDragging = true;
        this.dragStartX = e.touches[0].clientX;
        this.dragStartViewStart = this.viewStartTime;
        this.dragStartViewEnd = this.viewEndTime;
      } else if (e.touches.length === 2) {
        this.isDragging = false;
        this.initialPinchDistance = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY
        );
      }
    };

    this._handlers.onTouchMove = (e) => {
      if (e.touches.length === 1 && this.isDragging) {
        const plotWidth = this.width - this.paddingLeft - this.paddingRight;
        const deltaX = e.touches[0].clientX - this.dragStartX;
        const viewSpan = this.dragStartViewEnd - this.dragStartViewStart;
        const deltaTime = (deltaX / plotWidth) * viewSpan;

        this.viewStartTime = this.dragStartViewStart - deltaTime;
        this.viewEndTime = this.dragStartViewEnd - deltaTime;
        this.clampViewBounds();
        this.scheduleRender();
      } else if (e.touches.length === 2 && this.initialPinchDistance) {
        const dist = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY
        );
        const factor = this.initialPinchDistance / dist;
        const rect = this.canvas.getBoundingClientRect();
        const midX = (e.touches[0].clientX + e.touches[1].clientX) / 2 - rect.left;
        this.zoomAt(midX, factor);
        this.initialPinchDistance = dist;
      }
    };

    this._handlers.onTouchEnd = () => {
      this.isDragging = false;
      this.initialPinchDistance = null;
    };

    window.addEventListener('resize', this._handlers.onResize);
    this.canvas.addEventListener('mousedown', this._handlers.onMouseDown);
    window.addEventListener('mousemove', this._handlers.onMouseMove);
    window.addEventListener('mouseup', this._handlers.onMouseUp);
    this.canvas.addEventListener('mouseleave', this._handlers.onMouseLeave);
    this.canvas.addEventListener('wheel', this._handlers.onWheel, { passive: false });
    this.canvas.addEventListener('touchstart', this._handlers.onTouchStart, { passive: true });
    this.canvas.addEventListener('touchmove', this._handlers.onTouchMove, { passive: true });
    this.canvas.addEventListener('touchend', this._handlers.onTouchEnd);
  }

  zoom(factor) {
    const centerPlotX = this.paddingLeft + (this.width - this.paddingLeft - this.paddingRight) / 2;
    this.zoomAt(centerPlotX, factor);
  }

  zoomAt(canvasX, factor) {
    const plotX = this.paddingLeft;
    const plotWidth = this.width - this.paddingLeft - this.paddingRight;
    const currentSpan = this.viewEndTime - this.viewStartTime;

    const { minAllowed, maxAllowed } = this.getDatasetBounds();
    const maxAllowedSpan = maxAllowed - minAllowed;

    let newSpan = currentSpan * factor;
    if (newSpan < this.minViewSpan) newSpan = this.minViewSpan;
    if (newSpan > maxAllowedSpan) newSpan = maxAllowedSpan;

    const cursorRatio = Math.max(0, Math.min(1, (canvasX - plotX) / plotWidth));
    const cursorTime = this.viewStartTime + cursorRatio * currentSpan;

    this.viewStartTime = cursorTime - cursorRatio * newSpan;
    this.viewEndTime = cursorTime + (1 - cursorRatio) * newSpan;

    this.clampViewBounds();
    this.scheduleRender();
  }

  resetView() {
    this.viewStartTime = this.nightStart.getTime();
    this.viewEndTime = this.nightEnd.getTime();
    this.clampViewBounds();
    this.scheduleRender();
  }

  resizeCanvas() {
    if (!this.canvas || !this.container) return;
    const rect = this.container.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    this.width = rect.width || 800;
    this.height = rect.height || 320;

    this.canvas.width = this.width * dpr;
    this.canvas.height = this.height * dpr;
    this.canvas.style.width = `${this.width}px`;
    this.canvas.style.height = `${this.height}px`;

    if (this.ctx) {
      this.ctx.resetTransform();
      this.ctx.scale(dpr, dpr);
    }
  }

  timeToX(timestamp) {
    const plotX = this.paddingLeft;
    const plotWidth = this.width - this.paddingLeft - this.paddingRight;
    const ratio = (timestamp - this.viewStartTime) / (this.viewEndTime - this.viewStartTime);
    return plotX + ratio * plotWidth;
  }

  stageToY(stage, source = null) {
    const plotY = this.paddingTop;
    const plotHeight = this.height - this.paddingTop - this.paddingBottom;
    const bandHeight = plotHeight / 4;
    const level = this.stageLevels[stage] !== undefined ? this.stageLevels[stage] : 2;
    const bandTop = plotY + level * bandHeight;

    if (this.selectedSource === 'all') {
      if (source === 'apple_watch') {
        return bandTop + bandHeight * 0.25;
      } else if (source === 'oura') {
        return bandTop + bandHeight * 0.75;
      }
    }
    return bandTop + bandHeight * 0.5;
  }

  updateHoverState(mouseX, mouseY) {
    const plotX = this.paddingLeft;
    const plotWidth = this.width - this.paddingLeft - this.paddingRight;

    const prevHoveredId = this.hoveredInterval ? this.hoveredInterval.id : null;
    const prevMouseX = this.mousePos ? Math.round(this.mousePos.x) : null;
    const prevMouseY = this.mousePos ? Math.round(this.mousePos.y) : null;

    const roundedX = Math.round(mouseX);
    const roundedY = Math.round(mouseY);

    if (mouseX < plotX || mouseX > plotX + plotWidth) {
      const changed = this.hoveredInterval !== null || this.mousePos !== null;
      this.hoveredInterval = null;
      this.mousePos = null;
      if (this.tooltipEl) this.tooltipEl.style.display = 'none';
      return changed;
    }

    const hoverTime = this.viewStartTime + ((mouseX - plotX) / plotWidth) * (this.viewEndTime - this.viewStartTime);
    const visibleIntervals = this.getVisibleRenderIntervals();

    let interval = null;

    if (this.selectedSource === 'all') {
      const plotY = this.paddingTop;
      const plotHeight = this.height - this.paddingTop - this.paddingBottom;
      const bandHeight = plotHeight / 4;
      const levelIndex = Math.floor((mouseY - plotY) / bandHeight);
      if (levelIndex >= 0 && levelIndex < this.stages.length) {
        const targetStage = this.stages[levelIndex];
        const relY = (mouseY - plotY) % bandHeight;
        const targetSource = relY < bandHeight / 2 ? 'apple_watch' : 'oura';

        interval = visibleIntervals.find(inv =>
          inv.stage === targetStage &&
          inv.source === targetSource &&
          hoverTime >= inv.startTimestamp &&
          hoverTime <= inv.endTimestamp
        );
      }
    }

    if (!interval) {
      interval = visibleIntervals.find(inv => hoverTime >= inv.startTimestamp && hoverTime <= inv.endTimestamp);
    }

    this.hoveredInterval = interval;
    this.mousePos = { x: mouseX, y: mouseY };

    if (interval) {
      this.showTooltip(interval, mouseX, mouseY);
    } else if (this.tooltipEl) {
      this.tooltipEl.style.display = 'none';
    }

    const currentHoveredId = interval ? interval.id : null;
    const hasChanged = (currentHoveredId !== prevHoveredId) || (roundedX !== prevMouseX) || (roundedY !== prevMouseY);
    return hasChanged;
  }

  updateStats() {
    let dataset = this.getFilteredDataset();
    if (this.selectedSource === 'all') {
      // In 'all' sources view, calculate stats from primary dataset to prevent doubling duration values
      dataset = this.dataset.filter(d => d.source === 'apple_watch');
      if (this.statAttributionEl) {
        this.statAttributionEl.classList.remove('hidden');
      }
    } else if (this.statAttributionEl) {
      this.statAttributionEl.classList.add('hidden');
    }

    let totalSleepSec = 0;
    let deepSec = 0;
    let remSec = 0;
    let coreSec = 0;
    let awakeSec = 0;

    dataset.forEach(interval => {
      const dur = interval.durationSeconds;
      if (interval.stage === 'deep') deepSec += dur;
      else if (interval.stage === 'rem') remSec += dur;
      else if (interval.stage === 'core') coreSec += dur;
      else if (interval.stage === 'awake') awakeSec += dur;
    });

    totalSleepSec = deepSec + remSec + coreSec;

    const deepPct = totalSleepSec > 0 ? ((deepSec / totalSleepSec) * 100).toFixed(1) : '0';
    const remPct = totalSleepSec > 0 ? ((remSec / totalSleepSec) * 100).toFixed(1) : '0';
    const corePct = totalSleepSec > 0 ? ((coreSec / totalSleepSec) * 100).toFixed(1) : '0';

    if (this.statTotalEl) {
      this.statTotalEl.textContent = this.formatDuration(totalSleepSec);
      const statTotalLabel = this.statTotalLabelEl ||
        (this.statTotalEl.closest ? this.statTotalEl.closest('.stat-card') : this.statTotalEl.parentElement)?.querySelector('.stat-label');
      if (statTotalLabel) {
        if (this.selectedSource === 'all') {
          statTotalLabel.innerHTML = 'Total Sleep <span class="stat-source-badge" style="font-size: 0.75em; text-transform: none; opacity: 0.85; font-weight: normal;">(Apple Watch Primary)</span>';
        } else {
          statTotalLabel.textContent = 'Total Sleep';
        }
      }
    }
    if (this.statDeepEl) this.statDeepEl.textContent = `${this.formatDuration(deepSec)} (${deepPct}%)`;
    if (this.statRemEl) this.statRemEl.textContent = `${this.formatDuration(remSec)} (${remPct}%)`;
    if (this.statCoreEl) this.statCoreEl.textContent = `${this.formatDuration(coreSec)} (${corePct}%)`;
    if (this.statAwakeEl) this.statAwakeEl.textContent = this.formatDuration(awakeSec);
  }

  render() {
    if (!this.ctx || !this.canvas) return;

    const ctx = this.ctx;
    const width = this.width;
    const height = this.height;
    const plotX = this.paddingLeft;
    const plotY = this.paddingTop;
    const plotWidth = width - this.paddingLeft - this.paddingRight;
    const plotHeight = height - this.paddingTop - this.paddingBottom;
    const bandHeight = plotHeight / 4;
    const isMultiSource = this.selectedSource === 'all';

    // 1. Clear background
    ctx.clearRect(0, 0, width, height);

    // Canvas background fill
    ctx.fillStyle = '#070a1b';
    ctx.fillRect(0, 0, width, height);

    // 2. Draw Stage Horizontal Bands & Y-Axis Labels
    this.stages.forEach((stage, idx) => {
      const y = plotY + idx * bandHeight;

      // Subtle horizontal grid line
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.06)';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(plotX, y);
      ctx.lineTo(plotX + plotWidth, y);
      ctx.stroke();

      // Stage divider inside band for multi-source view
      if (isMultiSource) {
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.03)';
        ctx.beginPath();
        ctx.moveTo(plotX, y + bandHeight / 2);
        ctx.lineTo(plotX + plotWidth, y + bandHeight / 2);
        ctx.stroke();
      }

      // Y-Axis Stage Label
      ctx.fillStyle = this.stageColors[stage];
      ctx.font = '600 12px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif';
      ctx.textAlign = 'right';
      ctx.textBaseline = 'middle';
      ctx.fillText(this.stageLabels[stage], plotX - (isMultiSource ? 32 : 12), y + bandHeight / 2);

      if (isMultiSource) {
        ctx.font = '500 9px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif';
        ctx.fillStyle = '#60a5fa';
        ctx.fillText('AW', plotX - 8, y + bandHeight * 0.25);
        ctx.fillStyle = '#2dd4bf';
        ctx.fillText('Oura', plotX - 8, y + bandHeight * 0.75);
      }
    });

    // Bottom plot line boundary
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.1)';
    ctx.beginPath();
    ctx.moveTo(plotX, plotY + plotHeight);
    ctx.lineTo(plotX + plotWidth, plotY + plotHeight);
    ctx.stroke();

    // 3. Draw X-Axis Time Grid & Ticks
    const viewSpan = this.viewEndTime - this.viewStartTime;
    let tickInterval = 60 * 60 * 1000; // 1 hour tick by default
    if (viewSpan <= 3 * 60 * 60 * 1000) {
      tickInterval = 15 * 60 * 1000; // 15 mins
    } else if (viewSpan <= 6 * 60 * 60 * 1000) {
      tickInterval = 30 * 60 * 1000; // 30 mins
    }

    const firstTick = Math.ceil(this.viewStartTime / tickInterval) * tickInterval;
    ctx.fillStyle = '#64748b';
    ctx.font = '500 11px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';

    for (let t = firstTick; t <= this.viewEndTime; t += tickInterval) {
      const x = this.timeToX(t);
      if (x >= plotX && x <= plotX + plotWidth) {
        // Vertical grid line
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.04)';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(x, plotY);
        ctx.lineTo(x, plotY + plotHeight);
        ctx.stroke();

        // Time label
        const tickDate = new Date(t);
        const label = this.formatTime(tickDate);
        ctx.fillText(label, x, plotY + plotHeight + 10);
      }
    }

    // 4. Clip plot area for interval bars & stepped line
    ctx.save();
    ctx.beginPath();
    ctx.rect(plotX, plotY, plotWidth, plotHeight);
    ctx.clip();

    const visibleIntervals = this.getVisibleRenderIntervals();

    // Draw Filled Stage Interval Bars
    visibleIntervals.forEach(interval => {
      const x1 = this.timeToX(interval.startTimestamp);
      const x2 = this.timeToX(interval.endTimestamp);
      const barWidth = Math.max(x2 - x1, 2);
      const level = this.stageLevels[interval.stage];
      const y0 = plotY + level * bandHeight;
      const color = this.stageColors[interval.stage];

      let barY, barH;
      if (isMultiSource) {
        if (interval.source === 'apple_watch') {
          barY = y0 + 3;
          barH = Math.max(bandHeight / 2 - 4, 4);
        } else {
          barY = y0 + bandHeight / 2 + 1;
          barH = Math.max(bandHeight / 2 - 4, 4);
        }
      } else {
        barY = y0 + 4;
        barH = bandHeight - 8;
      }

      const isHovered = this.hoveredInterval && this.hoveredInterval.id === interval.id;

      // Bar Fill
      ctx.fillStyle = isHovered ? color : `${color}66`;
      ctx.beginPath();
      if (ctx.roundRect) {
        ctx.roundRect(x1, barY, barWidth, barH, 3);
      } else {
        ctx.rect(x1, barY, barWidth, barH);
      }
      ctx.fill();

      // Bar Stroke Outline
      ctx.strokeStyle = isMultiSource
        ? (interval.source === 'apple_watch' ? '#60a5fa' : '#2dd4bf')
        : color;
      ctx.lineWidth = isHovered ? 2 : 1;
      ctx.stroke();
    });

    // Draw Stepped Stage Architecture Line(s)
    if (isMultiSource) {
      ['apple_watch', 'oura'].forEach(source => {
        const sourceIntervals = visibleIntervals
          .filter(d => d.source === source)
          .sort((a, b) => a.startTimestamp - b.startTimestamp);

        if (sourceIntervals.length > 0) {
          ctx.beginPath();
          ctx.strokeStyle = source === 'apple_watch' ? 'rgba(96, 165, 250, 0.9)' : 'rgba(45, 212, 191, 0.9)';
          ctx.lineWidth = 1.5;
          if (source === 'oura') {
            ctx.setLineDash([4, 3]);
          } else {
            ctx.setLineDash([]);
          }

          let lastY = null;
          sourceIntervals.forEach((interval, idx) => {
            const x1 = this.timeToX(interval.startTimestamp);
            const x2 = this.timeToX(interval.endTimestamp);
            const y = this.stageToY(interval.stage, source);

            if (idx === 0) {
              ctx.moveTo(x1, y);
            } else {
              if (lastY !== null && lastY !== y) {
                ctx.lineTo(x1, lastY);
              }
              ctx.lineTo(x1, y);
            }
            ctx.lineTo(x2, y);
            lastY = y;
          });
          ctx.stroke();
          ctx.setLineDash([]);
        }
      });
    } else {
      const sortedIntervals = [...visibleIntervals].sort((a, b) => a.startTimestamp - b.startTimestamp);
      if (sortedIntervals.length > 0) {
        ctx.beginPath();
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.85)';
        ctx.lineWidth = 2;
        ctx.lineJoin = 'miter';

        let lastY = null;
        sortedIntervals.forEach((interval, idx) => {
          const x1 = this.timeToX(interval.startTimestamp);
          const x2 = this.timeToX(interval.endTimestamp);
          const y = this.stageToY(interval.stage);

          if (idx === 0) {
            ctx.moveTo(x1, y);
          } else {
            if (lastY !== null && lastY !== y) {
              ctx.lineTo(x1, lastY);
            }
            ctx.lineTo(x1, y);
          }
          ctx.lineTo(x2, y);
          lastY = y;
        });
        ctx.stroke();
      }
    }

    // 5. Draw Source Legend Badges in Multi-Source Mode
    if (isMultiSource) {
      ctx.font = '600 11px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif';

      // Apple Watch Legend Badge
      const awLabel = '⌚ Apple Watch';
      const awWidth = ctx.measureText(awLabel).width + 16;
      const awX = plotX + plotWidth - awWidth - 110;
      const legY = plotY - 20;

      ctx.fillStyle = 'rgba(15, 23, 42, 0.75)';
      ctx.strokeStyle = 'rgba(96, 165, 250, 0.6)';
      ctx.lineWidth = 1;
      if (ctx.roundRect) {
        ctx.beginPath();
        ctx.roundRect(awX, legY, awWidth, 18, 4);
        ctx.fill();
        ctx.stroke();
      } else {
        ctx.fillRect(awX, legY, awWidth, 18);
      }

      ctx.fillStyle = '#60a5fa';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(awLabel, awX + awWidth / 2, legY + 9);

      // Oura Ring Legend Badge
      const ouraLabel = '💍 Oura Ring';
      const ouraWidth = ctx.measureText(ouraLabel).width + 16;
      const ouraX = plotX + plotWidth - ouraWidth;

      ctx.fillStyle = 'rgba(15, 23, 42, 0.75)';
      ctx.strokeStyle = 'rgba(45, 212, 191, 0.6)';
      if (ctx.roundRect) {
        ctx.beginPath();
        ctx.roundRect(ouraX, legY, ouraWidth, 18, 4);
        ctx.fill();
        ctx.stroke();
      } else {
        ctx.fillRect(ouraX, legY, ouraWidth, 18);
      }

      ctx.fillStyle = '#2dd4bf';
      ctx.fillText(ouraLabel, ouraX + ouraWidth / 2, legY + 9);
    }

    // 6. Draw Interactive Hover Line Guide
    if (this.mousePos && this.mousePos.x >= plotX && this.mousePos.x <= plotX + plotWidth) {
      ctx.strokeStyle = 'rgba(129, 140, 248, 0.6)';
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 4]);
      ctx.beginPath();
      ctx.moveTo(this.mousePos.x, plotY);
      ctx.lineTo(this.mousePos.x, plotY + plotHeight);
      ctx.stroke();
      ctx.setLineDash([]);
    }

    ctx.restore();
  }

  destroy() {
    if (this.rafPending && typeof cancelAnimationFrame === 'function') {
      cancelAnimationFrame(this.rafId);
      this.rafPending = false;
    }

    // Unbind window listeners
    if (typeof window !== 'undefined' && this._handlers) {
      if (this._handlers.onResize) window.removeEventListener('resize', this._handlers.onResize);
      if (this._handlers.onMouseMove) window.removeEventListener('mousemove', this._handlers.onMouseMove);
      if (this._handlers.onMouseUp) window.removeEventListener('mouseup', this._handlers.onMouseUp);
    }

    // Unbind canvas listeners
    if (this.canvas && this._handlers) {
      if (this._handlers.onMouseDown) this.canvas.removeEventListener('mousedown', this._handlers.onMouseDown);
      if (this._handlers.onMouseLeave) this.canvas.removeEventListener('mouseleave', this._handlers.onMouseLeave);
      if (this._handlers.onWheel) this.canvas.removeEventListener('wheel', this._handlers.onWheel);
      if (this._handlers.onTouchStart) this.canvas.removeEventListener('touchstart', this._handlers.onTouchStart);
      if (this._handlers.onTouchMove) this.canvas.removeEventListener('touchmove', this._handlers.onTouchMove);
      if (this._handlers.onTouchEnd) this.canvas.removeEventListener('touchend', this._handlers.onTouchEnd);
    }

    // Unbind HUD listeners
    if (this._handlers) {
      if (this.sourceFilterSelect && this._handlers.onSourceChange) {
        this.sourceFilterSelect.removeEventListener('change', this._handlers.onSourceChange);
      }
      if (this.briefAwakeToggle && this._handlers.onBriefAwakeChange) {
        this.briefAwakeToggle.removeEventListener('change', this._handlers.onBriefAwakeChange);
      }
      if (this.zoomInBtn && this._handlers.onZoomIn) {
        this.zoomInBtn.removeEventListener('click', this._handlers.onZoomIn);
      }
      if (this.zoomOutBtn && this._handlers.onZoomOut) {
        this.zoomOutBtn.removeEventListener('click', this._handlers.onZoomOut);
      }
      if (this.resetViewBtn && this._handlers.onResetView) {
        this.resetViewBtn.removeEventListener('click', this._handlers.onResetView);
      }
    }

    // Remove tooltip
    if (this.tooltipEl && this.tooltipEl.parentNode) {
      this.tooltipEl.parentNode.removeChild(this.tooltipEl);
      this.tooltipEl = null;
    }

    this.container = null;
    this.canvas = null;
    this.ctx = null;
  }
}

// Global & Module Export
if (typeof window !== 'undefined') {
  window.SleepTimelineSimulator = SleepTimelineSimulator;
  document.addEventListener('DOMContentLoaded', () => {
    const simulatorWrapper = document.querySelector('.simulator-canvas-wrapper');
    if (simulatorWrapper && !window.sleepTimelineSimulatorInstance) {
      window.sleepTimelineSimulatorInstance = new SleepTimelineSimulator();
    }
  });
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = SleepTimelineSimulator;
}
