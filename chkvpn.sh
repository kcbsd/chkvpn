#!/bin/python3
# -*- codiong: utf-8 -*-
# Ver 0.96
import sys
import os
from selenium.webdriver import Chrome,ChromeOptions
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from time import sleep
import sys
import os
import re
import subprocess
import getopt
import datetime
import tempfile
import shutil
import inspect
gw_ip='192.168.3.8'
up_list='/etc/ppp/ip-up.d/0001vesca'
dn_list='/etc/ppp/ip-down.d/0001vesca'
up_out=['#!/bin/sh\n','systemctl start nftables\n']
dn_out=['#!/bin/sh\n']
driver=None
servers=[]
Force=False
Skip=False
HeadLess=True
DelAll=False
Verbose=False
CheckOnly=False
EraseOnly=False
fl=sys.stderr
def Quit(n):
	if driver!=None:
		driver.quit()
	if fl!=sys.stderr:
		fl.close()
	sys.exit(n)
def Fatal(msg):
		frame = inspect.currentframe().f_back
		if frame:
			print("line:%d %s"%(frame.f_lineno,msg))
		Quit(5)
def findElement(type,arg):
	maxcnt=3
	i=[]
	WebDriverWait(driver,10).until(EC.presence_of_all_elements_located)
	while len(i)==0 and maxcnt>0:
		i=driver.find_elements(type,arg)
		if len(i)==0:
			driver.refresh()
			maxcnt-=1
			continue
		return i[0]
	return None
def LoginSetting():
	passwd=findElement(By.NAME,'luci_password')
	if passwd==None:
		Fatal("serenium fatal error")
	passwd.clear()
	passwd.send_keys('kcbsd-Sayuri')
	login=findElement(By.ID,'loginBtn')
	login.click()
	setting=findElement(By.XPATH,'//*[@id="SPAccordionMenuDetails"]/p[2]/a')
	if setting==None:
		Fatal("serenium fatal error")
	setting.click()
	WebDriverWait(driver,10).until(EC.presence_of_all_elements_located)
def GetAMG(tr):
	tds=tr.find_elements(By.TAG_NAME,'td')
	if len(tds)==0:
		Fatal("serenium fatal error")
	if len(tds)==1:
		Fatal("tds[0] text:%s"%tds[0].text)
	s='%s/%s'%(tds[0].text,tds[1].text)
	return s
def RoutingList():
	d=driver.find_element(By.ID,"breadCrum")
	a=d.find_elements(By.TAG_NAME,'a')
	if len(a)==2:
		setting=driver.find_element(By.XPATH,'//*[@id="SPAccordionMenuTele"]/ul/li[3]/a')
		if setting==None:
			Fatal("serenium fatal error")
		setting.click()
		WebDriverWait(driver,10).until(EC.presence_of_all_elements_located)
	elif len(a)>2:
		driver.get(a[2].get_attribute('href'))
		driver.implicitly_wait(1)
	else:
		Fatal("len(a)<2")
def SaveSetting():
	saveBtn=findElement(By.ID,'commit_head')
	if saveBtn==None:
		Fatal("serenium fatal error")
	saveBtn.click()
	if Verbose:
		print("Saved",file=fl)
	WebDriverWait(driver,10).until(EC.presence_of_all_elements_located)
def GetTableTR():
	tbl=driver.find_elements(By.XPATH,'//*[@id="route_tbl"]/table')
	WebDriverWait(driver,10).until(EC.presence_of_all_elements_located)
	ret=driver.find_elements(By.TAG_NAME,'tr')
	if len(ret)==0:
		return None
	return ret[1:]
def DelRoute(tr):
	id=tr.get_attribute('id')
	s=GetAMG(tr)
	a=tr.find_element(By.XPATH,'//*[@id="%s"]/td[4]/p[2]/a'%id)
	a.click()
	WebDriverWait(driver,10).until(EC.alert_is_present())
	if Verbose:
		print("delete %s"%s,file=fl)
	alert=driver.switch_to.alert
	alert.accept()
	driver.implicitly_wait( 2 )
	driver.refresh()
def DelRouteAll():
	while True:
		trs=GetTableTR()
		n=len(trs)
		if Verbose:
			print("del cnt:%d"%n,file=fl)
		if n==0:
			break
		DelRoute(trs[n-1])
	if Verbose:
		print("Delete All Done",file=fl)
	SaveSetting()
	driver.refresh()
def SetRoute(amg):
	WebDriverWait(driver,10).until(EC.presence_of_all_elements_located)
	t=amg.split('/')
	inputs=driver.find_elements(By.TAG_NAME,'input')
	inputs[0].clear()
	inputs[1].clear()
	inputs[2].clear()
	inputs[0].send_keys(t[0])
	inputs[1].send_keys(t[1])
	inputs[2].send_keys(t[2])
	a=driver.find_element(By.ID,'iproute_change')
	driver.implicitly_wait( 2 ) 
	a.click()
	WebDriverWait(driver,30).until(EC.alert_is_present())
	alert=driver.switch_to.alert
	alert.accept()
	WebDriverWait(driver,120).until(EC.presence_of_element_located((By.ID, "resultMsg")))
	driver.implicitly_wait( 1 ) 
	RoutingList()
	driver.refresh()
	driver.implicitly_wait( 2 )
	if Verbose:
			print("Route %s set"%amg,file=fl)
	return True
def EditRoute(tr,amg):
	id=tr.get_attribute('id')
	a=tr.find_element(By.XPATH,'//*[@id="%s"]/td[4]/p[1]/a'%id)
	a.click()
	WebDriverWait(driver,10).until(EC.presence_of_all_elements_located)
	SetRoute(amg)
def AddRoute(amg):
	b=driver.find_element(By.ID,'addBtn')
	b.click()
	SetRoute(amg)
def Logout():
	b=driver.find_element(By.ID,'logout_head')
	b.click()
def AddList(d,s):
	cnt=0
	while cnt<len(d):
		if d[cnt]>s:
			d.insert(0,s)
			break
		cnt+=1
	if cnt==len(d):		
		d.append(s)
def flushRoute(keep,server,adr,gw,old):
	global servers
	ret=0
	if keep and len(adr)>0 and len(old)>0 and server!=None:
		c=len(adr)
		for a in adr:
			if not a in old:
				print("address %s not found in old list:%s"%(a,server),file=fl)
			else:
				c-=1
		if c>0:
			sys.exit(3)
		servers.append((server,old,gw,None))
		if Verbose:
			print("Server:%s append mode:%s"%(server,"keep"),file=fl)
	elif not keep and len(adr)>0 and server!=None:
		if old!=adr:
			ret=1
		servers.append((server,adr,gw,old))
		if Verbose:
			print("Server:%s append mode:%s"%(server,"norm" ),file=fl)
	return ret
def chgList(arg):
	global servers
	ret=0
	server=None
	gw=None
	keep=False
	adr=[]
	old=[]
	t=subprocess.check_output(arg,shell=True).decode().split('\n')
	if Verbose:
		print("arg:%s %d lines"%(arg,len(t)),file=fl)
	cnt=0
	for s in t:
		cnt+=1
		if s.strip()[0:2] == '##' or s.strip()[0:2] == '# ':
			ret+=flushRoute(keep,server,adr,gw,old)
			keep=True if s.strip()[0:2] == '##' else False
			gw=None
			adr=[]
			old=[]
			server=s[2:].strip()
			n=subprocess.check_output("dig %s"%(server),shell=True).decode().split('\n')
			if Verbose:
				print("dig:%s %d lines"%(server,len(n)),file=fl)
			for l in n:
				if l[0:1]!=';':
					f=l.split()
					if len(f)==5 and f[3]=='A' and f[2]=='IN' :
						AddList(adr,"%s/32"%f[4])
						if Verbose:
							print("adr:%s append norm"%f[4],file=fl)
		else:
			r=s.split()
			if len(r)>4 and r[0]=='route' :
				if gw==None:
					gw=r[4]
				AddList(old,"%s/32"%r[2])
				if Verbose:
					print("old:%s append"%r[2],file=fl)
		if Verbose:
			print("%d processed :%s"%(cnt,s),file=fl)
	if server!=None and len(adr)>0:
		ret+=flushRoute(keep,server,adr,gw,old)
	return ret
def CheckDuplicate(trs,adrs):
	i=0
	while i<len(adrs):
		j=i+1
		while j<len(trs):
			if GetAMG(trs[j])==adrs[i]:
				return True
			j+=1
		i+=1
	return False
def logOpen(a):
	try:
		f=open(a,mode='a')
	except OSError as e:
		print(e,file=sys.stderr)
		os.exit(1)
	else:
		return f
###############################################################################
try:
	opts,args = getopt.getopt( sys.argv[1:], "fsgdcvel:", ["force","skiproute","gui","delall","erase","log="] )
except getopt.GetoptError as err:
	print(str(err))
	sys.exit(2)
for o,a in opts:
	match o:
		case "-f" | "--force":
			Force=True
		case "-s" | "--skiproute":
			Skip=True
		case "-g" | "--gui":
			HeadLess=False
		case "-d" | "--delall":
			DelAll=True
		case "-c" | "--check":
			CheckOnly=True
		case "-v" | "--verbose":
			Verbose=True
		case "-e" | "--erase":
			EraseOnly=True
		case "-l" | "--log":
			fl=logOpen(a)
chg=chgList('ssh root@%s cat %s'%(gw_ip,up_list))
if not Force and not EraseOnly and chg==0:
	print("Same Setting",file=fl)
	sys.exit(0)
if CheckOnly:
	print("%s differ Setting"%chg,file=fl)
	for s,aa,g,oo in servers:
		sd=0
		if oo!=None and aa!=oo:
			if sd==0:
				print("server:%s"%s,file=fl)
				sd=1
			for a in aa:
				if not a in oo:
					print(" new:%s"%a,file=fl)
			for o in oo:
				if not o in aa:
					print(" del:%s"%o,file=fl)
	sys.exit(1)
dir=tempfile.mkdtemp()
fu=open("%s/up.d"%dir,mode='w')
fd=open("%s/dn.d"%dir,mode='w')
d=[]
u=[]
adrs=[]
for s,aa,g,o in servers:
	if o==None:
		d.append('##%s\n'%s)
		u.append('##%s\n'%s)
	else:
		d.append('# %s\n'%s)
		u.append('# %s\n'%s)
	for a in aa:
		adrs.append("%s/%s"%(a,gw_ip))
		u.append('route add %s gw %s\n'%(a.split('/')[0],g))
		d.append('route del %s gw %s\n'%(a.split('/')[0],g))
if Verbose:
	print("adrs:%d address reading tempdir:%s"%(len(adrs),dir))
adrs.append('192.168.2.0/24/192.168.3.5')
up_out.extend(u)
dn_out.extend(d)
up_out.append('exit 0\n')
dn_out.append('systemctl stop nftables\n')
dn_out.append('exit 0\n')

fu.writelines(up_out)
fd.writelines(dn_out)
fu.close()
fd.close()
subprocess.run(["scp", 'root@%s:%s'%(gw_ip,up_list),'%s.bak'%os.path.basename(up_list)],stdout=subprocess.DEVNULL,stderr=fl)
subprocess.run(["ssh",'root@%s'%gw_ip,'systemctl','stop','xl2tpd'],stdout=subprocess.DEVNULL,stderr=fl)
subprocess.run(["scp",'%s/up.d'%dir,'root@%s:%s'%(gw_ip,up_list)],stdout=subprocess.DEVNULL,stderr=fl)
subprocess.run(["scp",'%s/dn.d'%dir,'root@%s:%s'%(gw_ip,dn_list)],stdout=subprocess.DEVNULL,stderr=fl)
shutil.rmtree(dir)
if Skip:
	Quit(0)
print("Total:%d"%len(adrs),file=fl)
options= ChromeOptions()
if HeadLess:
	options.add_argument('--headless')
	options.add_argument('--window-size=1920,1080')
if os.environ['OSTYPE']=='FreeBSD':
	drv_path='/usr/local/bin/chromedriver'
	options.binary_location='/usr/local/bin/chrome'
else:
	drv_path='/usr/bin/chromedriver'
driver= Chrome(service=Service(drv_path),options=options)
driver.get('http://192.168.3.1/cgi-bin/gui/default/system')
LoginSetting()
RoutingList()
lenAdrs=len(adrs)
trs= GetTableTR()
if len(trs)>lenAdrs or CheckDuplicate(trs,adrs):
	DelAll=True
if not DelAll and not EraseOnly:
	src=0
	dst=0
	while not DelAll and src<lenAdrs:
		if dst<len(trs):
			driver.implicitly_wait( 2 )
			chg=0
			while GetAMG(trs[dst])!=adrs[src]:
				chg=1
				if Verbose:
					print("%d,%d:%s!=%s"%(dst,src,GetAMG(trs[dst]),adrs[src]),file=fl)
				EditRoute(trs[dst],adrs[src])
				WebDriverWait(driver,5).until(EC.presence_of_all_elements_located)
				trs= GetTableTR()
			if Verbose and chg==0:
				print("%d,%d:%s==%s"%(dst,src,GetAMG(trs[dst]),adrs[src]),file=fl)
			src+=1
		else:
			while len(trs)<dst:
				AddRoute(adrs[src])
				WebDriverWait(driver,5).until(EC.presence_of_all_elements_located)
				trs= GetTableTR()
				if (src+1)==len(trs):
					src+=1
					break
		dst+=1
if DelAll or EraseOnly:
	DelRouteAll()
	if EraseOnly:
		b=driver.find_element(By.ID,'logout_head')
		b.click()
		Quit(0)
	# WebDriverWait(driver,120).until(EC.presence_of_all_elements_located)
	cnt=0
	for a in adrs:
		cnt+=1
		print("addr:%s cnt:%d"%(a,cnt),file=fl)
		while True:
			AddRoute(a)
			WebDriverWait(driver,5).until(EC.presence_of_all_elements_located)
			trs= GetTableTR()
			n=len(trs)
			print("add trs:%d"%n,file=fl)
			if n==cnt:
				break
SaveSetting()
Logout()
subprocess.run(["ssh",'root@%s'%gw_ip,'systemctl','start','xl2tpd'],stdout=subprocess.DEVNULL,stderr=fl)
Quit(0)
