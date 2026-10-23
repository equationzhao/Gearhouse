import {randomUUID} from 'node:crypto';

export const builtinCategories = [
 ['Bike','自行车'],['Shoes','跑鞋'],['CyclingShoes','锁鞋'],['Cleats','锁片'],
 ['Pedals','锁踏'],['PowerMeter','功率计'],['Handlebar','车把'],['Saddle','坐垫'],['Seatpost','坐杆'],
 ['Chainrings','牙盘'],['Crankset','曲柄'],['Spider','盘爪'],
 ['Wheelset','轮组'],['Tyre','轮胎'],['Tube','内胎'],['BrakePads','来令片'],['BrakeRotor','碟片'],
 ['Cassette','飞轮'],['Chain','链条'],['FrontDerailleur','前变速器'],['RearDerailleur','后变速器'],['Trainer','骑行台'],['Equipment','其他装备']
].map(([id,name])=>({id,name,baseType:id,builtin:true,indoorDistance:['Trainer','Chain','Cassette','Chainrings','Crankset','Spider','FrontDerailleur','RearDerailleur'].includes(id)}));
const addedCategoryIDs=new Set(['BrakePads','BrakeRotor','Saddle','Seatpost','FrontDerailleur','RearDerailleur','Crankset','Spider']);
function check(ok,message){if(!ok)throw Error(message);}
function nameKey(name){return name.trim().toLowerCase();}

function migrateCategoryTypes(s){
 const wheel=s.gearCategories.find(c=>c?.id==='Wheel');
 if(wheel&&!s.gearCategories.some(c=>c?.id==='Wheelset'))s.gearCategories.push({...wheel,id:'Wheelset',name:'轮组',baseType:'Wheelset',builtin:true});
 for(const gear of s.gears){
  if(gear.categoryId==='Wheel')gear.categoryId='Wheelset';
  if(gear.type==='Wheel'){gear.type='Wheelset';gear.categoryId??='Wheelset';}
  if(gear.type==='Drivetrain'){
   gear.categoryId??='Drivetrain';gear.type='Equipment';
   if(gear.categoryId==='Drivetrain'&&!s.gearCategories.some(c=>c?.id==='Drivetrain'))s.gearCategories.push({id:'Drivetrain',name:'传动系统',baseType:'Equipment',builtin:false,indoorDistance:true});
  }
 }
 s.gearCategories=s.gearCategories.filter(c=>c?.id!=='Wheel'&&(c?.id!=='Drivetrain'||s.gears.some(g=>g.categoryId===c.id)||c.name!=='传动系统'));
 for(const category of s.gearCategories){
  if(category?.baseType==='Wheel')category.baseType='Wheelset';
  if(category?.baseType==='Drivetrain')category.baseType='Equipment';
 }
}

export function ensureCategories(s){
 if(s.gearCategories===undefined)s.gearCategories=builtinCategories.map(c=>({...c}));
 check(Array.isArray(s.gearCategories),'无法读取装备类别，请选择完整备份。');
 migrateCategoryTypes(s);
 const ids=new Set(),names=new Set();
 for(const c of s.gearCategories){
  check(c&&typeof c.id==='string'&&c.id.length>0&&!ids.has(c.id),'备份中的装备类别重复或损坏，请重新导出备份。');
  check(typeof c.name==='string'&&c.name.trim().length>0&&c.name.length<=80&&!names.has(nameKey(c.name)),'备份中的装备类别名称重复或损坏，请重新导出备份。');
  check(builtinCategories.some(b=>b.id===c.baseType)&&typeof c.indoorDistance==='boolean','无法读取装备类别，请选择完整备份。');
  const builtin=builtinCategories.find(b=>b.id===c.id);
  check(!builtin||c.baseType===builtin.baseType,'内置类别的基础类型不能修改。');
  c.builtin=!!builtin;ids.add(c.id);names.add(nameKey(c.name));
 }
 for(const builtin of builtinCategories)if(!ids.has(builtin.id)){
  // Keep an existing user category when a newly added default has the same name.
  if(addedCategoryIDs.has(builtin.id)&&names.has(nameKey(builtin.name)))continue;
  check(!names.has(nameKey(builtin.name)),'备份中的装备类别名称重复或损坏，请重新导出备份。');
  s.gearCategories.push({...builtin});ids.add(builtin.id);names.add(nameKey(builtin.name));
 }
 for(const gear of s.gears){
  if(gear.categoryId){
   const category=s.gearCategories.find(c=>c.id===gear.categoryId);
   check(category,'装备的类别已不存在，请检查备份。');
   check(gear.type===category.baseType||category.legacyType&&gear.type===category.legacyType,'备份中的装备类别不一致，请重新导出备份。');
   continue;
  }
  const type=gear.type||'Equipment';
  let category=s.gearCategories.find(c=>c.id===type||c.legacyType===type);
  const builtin=builtinCategories.find(c=>c.id===type);
  if(!category&&builtin){category=s.gearCategories.find(c=>nameKey(c.name)===nameKey(builtin.name));if(category)gear.type=category.baseType;}
  if(!category){
   let name=type,suffix=1;while(names.has(nameKey(name)))name=type+' '+(++suffix);
   category={id:randomUUID(),name,baseType:'Equipment',builtin:false,indoorDistance:false,legacyType:type};
   s.gearCategories.push(category);ids.add(category.id);names.add(nameKey(name));
  }
  gear.categoryId=category.id;
 }
 return s;
}
export function saveCategory(s,input){
 const existing=input.id?s.gearCategories.find(c=>c.id===input.id):null;
 check(!input.id||existing,'类别已不存在，请重新打开。');
 const name=String(input.name||'').trim();
 check(name.length>0&&name.length<=80,'请填写类别名称，最多 80 字。');
 check(!s.gearCategories.some(c=>c.id!==existing?.id&&nameKey(c.name)===nameKey(name)),'已有同名类别，请使用其他名称。');
 const baseType=input.baseType||existing?.baseType||'Equipment';
 check(builtinCategories.some(c=>c.id===baseType),'请选择基础类型。');
 check(!existing?.builtin||baseType===existing.baseType,'内置类别的基础类型不能修改。');
 check(!existing||baseType===existing.baseType||!s.gears.some(g=>g.categoryId===existing.id),'该类别已有装备，不能修改基础类型。');
 check(typeof input.indoorDistance==='boolean','请选择是否计入室内骑行距离。');
 const category={...existing,id:existing?.id||randomUUID(),name,baseType,builtin:!!existing?.builtin,indoorDistance:input.indoorDistance};
 if(existing)Object.assign(existing,category);else s.gearCategories.push(category);
 return category;
}
export function deleteCategory(s,input){
 const category=s.gearCategories.find(c=>c.id===input.id);
 check(category,'类别已不存在，请重新打开。');
 check(!category.builtin,'内置类别不能删除。');
 check(input.confirmed===true,'请确认删除类别。');
 const gears=s.gears.filter(g=>g.categoryId===category.id);
 if(gears.length){
  const replacement=s.gearCategories.find(c=>c.id===input.replacementId&&c.id!==category.id);
  check(replacement,'请为关联装备选择替代类别。');
  check(replacement.baseType===category.baseType,'请选择相同基础类型的替代类别。');
  for(const gear of gears){gear.categoryId=replacement.id;gear.type=replacement.baseType;}
 }
 s.gearCategories=s.gearCategories.filter(c=>c.id!==category.id);
 return {moved:gears.length};
}
