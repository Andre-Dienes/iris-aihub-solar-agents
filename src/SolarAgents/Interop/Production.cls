/// Demo production: every agent is a business process, so each question shows up end-to-end in the
/// Visual Trace (Gateway -> Agent.Router -> Agent.Telemetry / Agent.Weather / Agent.Maintenance),
/// and the assistant's actions reach a business operation (WorkOrders).
Class SolarAgents.Interop.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="SolarAgents.Interop.Production" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>IRIS AI Hub — solar plant agents (demo)</Description>
  <ActorPoolSize>2</ActorPoolSize>
  <Item Name="Gateway" Category="Demo" ClassName="SolarAgents.Interop.Gateway" PoolSize="0" Enabled="true" Foreground="false" Comment="Entry point for questions and actions" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="Agent.Router" Category="Demo,Agents" ClassName="SolarAgents.Interop.AgentProcess" PoolSize="2" Enabled="true" Foreground="false" Comment="Multi-agent router" LogTraceEvents="false" Schedule="">
    <Setting Target="Host" Name="AgentClass">SolarAgents.Agent.Router</Setting>
  </Item>
  <Item Name="Agent.Telemetry" Category="Demo,Agents" ClassName="SolarAgents.Interop.AgentProcess" PoolSize="2" Enabled="true" Foreground="false" Comment="Telemetry (text-to-SQL)" LogTraceEvents="false" Schedule="">
    <Setting Target="Host" Name="AgentClass">SolarAgents.Agent.Telemetry</Setting>
  </Item>
  <Item Name="Agent.Weather" Category="Demo,Agents" ClassName="SolarAgents.Interop.AgentProcess" PoolSize="2" Enabled="true" Foreground="false" Comment="Weather (text-to-SQL)" LogTraceEvents="false" Schedule="">
    <Setting Target="Host" Name="AgentClass">SolarAgents.Agent.Weather</Setting>
  </Item>
  <Item Name="Agent.Maintenance" Category="Demo,Agents" ClassName="SolarAgents.Interop.AgentProcess" PoolSize="2" Enabled="true" Foreground="false" Comment="Maintenance (text-to-SQL)" LogTraceEvents="false" Schedule="">
    <Setting Target="Host" Name="AgentClass">SolarAgents.Agent.Maintenance</Setting>
  </Item>
  <Item Name="WorkOrders" Category="Demo,Actions" ClassName="SolarAgents.Interop.WorkOrderOperation" PoolSize="1" Enabled="true" Foreground="false" Comment="Opens maintenance work orders" LogTraceEvents="false" Schedule="">
  </Item>
</Production>
}

}
