function campusSlideshow(){return `<div class="campus-slides" aria-label="University life slideshow" aria-roledescription="carousel"><img class="campus-slide active" src="/static/media/campus/classroom.png" alt="Diverse university students collaborating around a classroom table" fetchpriority="high"><img class="campus-slide" src="/static/media/campus/library.png" alt="Diverse university students studying together in a sunlit library" aria-hidden="true"><div class="campus-shade"></div></div><div class="campus-controls"><span class="campus-caption">Learning together · 1 / 2</span><button type="button" aria-label="Previous campus photo">←</button><button type="button" aria-label="Pause campus slideshow">Pause</button><button type="button" aria-label="Next campus photo">→</button><small>AI-generated campus scenes</small></div>`}
function bindCampusSlideshow(){
 const root=document.querySelector('.landing-hero'),slides=[...root.querySelectorAll('.campus-slide')],buttons=root.querySelectorAll('.campus-controls button'),caption=root.querySelector('.campus-caption');
 const motion=matchMedia('(prefers-reduced-motion: reduce)');let current=0,paused=motion.matches,visible=true;
 function show(index){current=(index+slides.length)%slides.length;slides.forEach((s,i)=>{s.classList.toggle('active',i===current);s.setAttribute('aria-hidden',String(i!==current))});caption.textContent=`${current?'Growing together':'Learning together'} · ${current+1} / ${slides.length}`}
 function state(){buttons[1].textContent=paused?'Play':'Pause';buttons[1].setAttribute('aria-label',`${paused?'Play':'Pause'} campus slideshow`)}
 buttons[0].onclick=()=>show(current-1);buttons[2].onclick=()=>show(current+1);buttons[1].onclick=()=>{paused=!paused;state()};state();
 const observer=new IntersectionObserver(entries=>{visible=entries[0].isIntersecting});observer.observe(root);
 const timer=setInterval(()=>{if(!root.isConnected){clearInterval(timer);observer.disconnect();return}if(!paused&&visible&&!document.hidden&&!root.matches(':hover')&&!root.contains(document.activeElement))show(current+1)},6000);
 motion.addEventListener('change',e=>{if(e.matches){paused=true;state()}});
}
