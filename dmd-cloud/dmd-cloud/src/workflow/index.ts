import { Workflow } from './workflowTypes';

export class WorkflowManager {
    private workflows: Workflow[];

    constructor() {
        this.workflows = [];
    }

    public addWorkflow(workflow: Workflow): void {
        this.workflows.push(workflow);
    }

    public runAll(): void {
        this.workflows.forEach(workflow => {
            console.log(`Running workflow: ${workflow.name}`);
            workflow.execute();
        });
    }
}

// Example of a workflow execution function
export function exampleWorkflow() {
    console.log('Executing example workflow...');
    // Add workflow logic here
}