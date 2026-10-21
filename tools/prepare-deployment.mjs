import fs from 'node:fs';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..');
const entries = [
  ['ReplicatedStorage/DeadblockShared/Config', 'ModuleScript', 'src/shared/Config.luau'],
  ...['ProductionModel','PlotRegistry','TycoonModel','PlayerStateService','BaseService','ProductionService','PurchaseService'].map(name => [`ServerScriptService/Deadblock/${name}`, 'ModuleScript', `src/server/${name}.luau`]),
  ['StarterPlayer/StarterPlayerScripts/DeadblockHUD', 'LocalScript', 'src/client/HUD.client.luau'],
  ['ServerStorage/DeadblockTests/Stage1Spec', 'ModuleScript', 'tests/Stage1.spec.luau'],
  ['ServerStorage/DeadblockTests/Stage2Spec', 'ModuleScript', 'tests/Stage2.spec.luau'],
  ['ServerScriptService/Deadblock/Main', 'Script', 'src/server/Main.server.luau'],
];
let code = `local installed = {}\nlocal function put(path, className, source)\n local segments=string.split(path,'/') local parent=game:GetService(segments[1])\n for i=2,#segments-1 do local nextNode=parent:FindFirstChild(segments[i]) if not nextNode then nextNode=Instance.new('Folder') nextNode.Name=segments[i] nextNode.Parent=parent end parent=nextNode end\n local name=segments[#segments] local node=parent:FindFirstChild(name) if node then assert(node.ClassName==className,'Class conflict: '..path) else node=Instance.new(className) node.Name=name node.Parent=parent end\n node.Source=source table.insert(installed,path)\nend\n`;
code=code.replace('node.Source=source',"if node:IsA('ModuleScript') then node:Destroy() node=Instance.new(className) node.Name=name node.Parent=parent end node.Source=source");
for (const [target, type, source] of entries) {
  const content = fs.readFileSync(path.join(root, source), 'utf8');
  if (content.includes(']====]')) throw new Error('Delimiter collision');
  code += `put(${JSON.stringify(target)}, ${JSON.stringify(type)}, [====[${content}]====])\n`;
}
code += `local remotes=game.ReplicatedStorage:FindFirstChild('DeadblockRemotes') if not remotes then remotes=Instance.new('Folder') remotes.Name='DeadblockRemotes' remotes.Parent=game.ReplicatedStorage end for _,name in ipairs({'TycoonAction','Feedback'}) do if not remotes:FindFirstChild(name) then local event=Instance.new('RemoteEvent') event.Name=name event.Parent=remotes end end return {installed=installed,count=#installed}`;
fs.writeFileSync(path.join(root, 'tools', 'Deploy.generated.luau'), code);
console.log(`Prepared ${entries.length} scripts`);
